/**
 * `syncLedger` callable: validates client-authored ledger entries against the
 * economy bounds, stores accepted and rejected entries idempotently under
 * `users/{uid}/ledger/{id}` and maintains the authoritative balance in
 * `users/{uid}.wallet.balance` (= sum of accepted entries, seeded with the
 * starting wallet). Once-per-ref and per-day rules use marker documents under
 * `users/{uid}/claims`.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { EARN_RULES, isEarnType, isServerOnlyType, isSpendType, MAX_ENTRIES_PER_SYNC, SPEND_LIMITS } from '../economy';
import { type Db, type DocData, type DocSnapshot, readNumber, readString, safeDocId } from '../lib/firestore';
import { DAY_MS, isoDate } from '../lib/time';
import { validate } from '../lib/validate';
import { readWallet, STARTING_WALLET_ENTRY_ID, startingWalletEntry, walletUpdate } from '../lib/wallet';

export interface ClientLedgerEntry {
  id: string;
  type: string;
  amount: number;
  balanceAfter: number;
  createdAt: number;
  deviceId: string;
  refId: string | null;
  lang?: string;
}

export interface RejectedEntry {
  id: string;
  reason: string;
}

export interface SyncLedgerResult {
  accepted: string[];
  rejected: RejectedEntry[];
  balance: number;
}

/** Entries whose createdAt is older than this are refused, which keeps the per-day caps meaningful. */
export const MAX_ENTRY_AGE_MS = 7 * DAY_MS;
/** Clock skew tolerated for entries dated in the future. */
export const MAX_FUTURE_SKEW_MS = 5 * 60_000;

export function ledgerPath(uid: string, id: string): string {
  return `users/${uid}/ledger/${id}`;
}
export function refClaimPath(uid: string, type: string, refId: string): string {
  return `users/${uid}/claims/${safeDocId(`${type}~${refId}`)}`;
}
export function dayClaimPath(uid: string, type: string, date: string): string {
  return `users/${uid}/claims/${safeDocId(`${type}~day~${date}`)}`;
}

interface Pending {
  id: string;
  raw: Record<string, unknown>;
  entry?: ClientLedgerEntry;
  /** Rejection decided before looking at stored state. */
  earlyReason?: string;
  refClaim?: string;
  dayClaim?: string;
  day?: string;
}

function parseInput(input: unknown): Record<string, unknown>[] {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new HttpsError('invalid-argument', 'expected an object with an `entries` array');
  }
  const entries = (input as { entries?: unknown }).entries;
  if (!Array.isArray(entries)) throw new HttpsError('invalid-argument', '`entries` must be an array');
  if (entries.length === 0) throw new HttpsError('invalid-argument', '`entries` must not be empty');
  if (entries.length > MAX_ENTRIES_PER_SYNC) {
    throw new HttpsError('invalid-argument', `at most ${MAX_ENTRIES_PER_SYNC} entries per call (got ${entries.length})`);
  }
  return entries.map((e, i) => {
    if (typeof e !== 'object' || e === null || Array.isArray(e)) throw new HttpsError('invalid-argument', `entries[${i}] must be an object`);
    const id = (e as { id?: unknown }).id;
    if (typeof id !== 'string' || id.length === 0 || id.length > 64) {
      throw new HttpsError('invalid-argument', `entries[${i}].id must be a non-empty string of at most 64 characters`);
    }
    return e as Record<string, unknown>;
  });
}

function prepare(uid: string, raw: Record<string, unknown>, now: number): Pending {
  const id = raw['id'] as string;
  if ('server' in raw) return { id, raw, earlyReason: 'the `server` field is reserved for Cloud Functions' };
  const result = validate('ledger-entry', raw);
  if (!result.ok) return { id, raw, earlyReason: `schema: ${result.errors.join('; ')}` };
  const entry = raw as unknown as ClientLedgerEntry;
  const pending: Pending = { id, raw, entry };
  if (isServerOnlyType(entry.type)) {
    pending.earlyReason = `type ${entry.type} may only be written by the server`;
  } else if (entry.createdAt > now + MAX_FUTURE_SKEW_MS) {
    pending.earlyReason = 'createdAt is in the future';
  } else if (entry.createdAt < now - MAX_ENTRY_AGE_MS) {
    pending.earlyReason = `createdAt is older than ${MAX_ENTRY_AGE_MS / DAY_MS} days`;
  } else if (isEarnType(entry.type)) {
    const rule = EARN_RULES[entry.type];
    if (!(entry.amount > 0)) {
      pending.earlyReason = 'earn amount must be positive';
    } else if (entry.amount > rule.max) {
      pending.earlyReason = `amount ${entry.amount} exceeds the ${entry.type} cap of ${rule.max}`;
    } else {
      if (rule.oncePerRef) {
        if (entry.refId === null) pending.earlyReason = `${entry.type} requires a refId`;
        else pending.refClaim = refClaimPath(uid, entry.type, entry.refId);
      }
      if (rule.perDay !== undefined) {
        pending.day = isoDate(entry.createdAt);
        pending.dayClaim = dayClaimPath(uid, entry.type, pending.day);
      }
    }
  } else if (isSpendType(entry.type)) {
    const limit = SPEND_LIMITS[entry.type];
    if (!(entry.amount < 0)) pending.earlyReason = 'spend amount must be negative';
    else if (-entry.amount > limit) pending.earlyReason = `spend of ${-entry.amount} exceeds the ${entry.type} price cap of ${limit}`;
  }
  // `reconcile` entries carry no bounds beyond the schema and never move coins.
  return pending;
}

function rejectedDoc(p: Pending, reason: string, now: number): DocData {
  const pick = (key: string, type: 'string' | 'number'): unknown => (typeof p.raw[key] === type ? p.raw[key] : null);
  return {
    id: p.id,
    type: pick('type', 'string'),
    amount: pick('amount', 'number'),
    balanceAfter: pick('balanceAfter', 'number'),
    createdAt: pick('createdAt', 'number'),
    deviceId: pick('deviceId', 'string'),
    refId: pick('refId', 'string'),
    server: { status: 'rejected', source: 'client', reason, syncedAt: now, appliedAmount: 0 },
  };
}

function compareEntries(a: Pending, b: Pending): number {
  const ta = a.entry?.createdAt ?? 0;
  const tb = b.entry?.createdAt ?? 0;
  if (ta !== tb) return ta - tb;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

export async function syncLedger(db: Db, uid: string, input: unknown, now: number): Promise<SyncLedgerResult> {
  const raws = parseInput(input);
  const seen = new Set<string>();
  const duplicates: RejectedEntry[] = [];
  const pendings: Pending[] = [];
  for (const raw of raws) {
    const id = raw['id'] as string;
    if (seen.has(id)) {
      duplicates.push({ id, reason: 'duplicate id within the request' });
      continue;
    }
    seen.add(id);
    pendings.push(prepare(uid, raw, now));
  }
  pendings.sort(compareEntries);

  return db.runTransaction(async (tx) => {
    const userPath = `users/${uid}`;
    const claimPaths = [...new Set(pendings.flatMap((p) => [p.refClaim, p.dayClaim].filter((x): x is string => x !== undefined)))];
    // All reads first (Firestore forbids reads after the first write in a transaction).
    const [user, existing, claimSnaps] = await Promise.all([
      tx.get(userPath),
      Promise.all(pendings.map((p) => tx.get(ledgerPath(uid, p.id)))),
      Promise.all(claimPaths.map((c) => tx.get(c))),
    ]);
    const claimByPath = new Map<string, DocSnapshot>();
    claimPaths.forEach((c, i) => claimByPath.set(c, claimSnaps[i] as DocSnapshot));
    const refClaimed = new Set(claimPaths.filter((c) => claimByPath.get(c)?.exists === true));
    const dayCounts = new Map<string, number>();
    for (const c of claimPaths) dayCounts.set(c, readNumber(claimByPath.get(c)?.data, 'count', 0));

    const wallet = readWallet(user);
    let balance = wallet.balance;
    const accepted: string[] = [];
    const rejected: RejectedEntry[] = [...duplicates];
    const writes: Array<{ path: string; data: DocData }> = [];

    pendings.forEach((p, i) => {
      const prior = existing[i] as DocSnapshot;
      const priorStatus = readString(prior.data, 'server.status');
      if (prior.exists && priorStatus === 'accepted') {
        accepted.push(p.id); // idempotent replay
        return;
      }
      if (prior.exists && priorStatus === 'rejected') {
        rejected.push({ id: p.id, reason: readString(prior.data, 'server.reason') ?? 'rejected by an earlier sync' });
        return;
      }
      const entry = p.entry;
      let reason = p.earlyReason;
      if (reason === undefined && entry !== undefined) {
        if (p.refClaim !== undefined && refClaimed.has(p.refClaim)) {
          reason = `${entry.type} was already credited for ${entry.refId ?? ''}`;
        } else if (p.dayClaim !== undefined && isEarnType(entry.type)) {
          const cap = EARN_RULES[entry.type].perDay ?? Number.POSITIVE_INFINITY;
          if ((dayCounts.get(p.dayClaim) ?? 0) >= cap) reason = `daily cap of ${cap} ${entry.type} entries reached for ${p.day ?? ''}`;
        }
        if (reason === undefined && isSpendType(entry.type) && balance + entry.amount < 0) {
          reason = `insufficient balance: ${balance} ${entry.amount} < 0`;
        }
      }
      if (reason !== undefined || entry === undefined) {
        const why = reason ?? 'invalid entry';
        rejected.push({ id: p.id, reason: why });
        writes.push({ path: ledgerPath(uid, p.id), data: rejectedDoc(p, why, now) });
        return;
      }
      const applied = entry.type === 'reconcile' ? 0 : entry.amount;
      balance += applied;
      accepted.push(entry.id);
      writes.push({
        path: ledgerPath(uid, p.id),
        data: { ...(entry as unknown as DocData), balanceAfter: balance, server: { status: 'accepted', source: 'client', syncedAt: now, appliedAmount: applied } },
      });
      if (p.refClaim !== undefined) {
        refClaimed.add(p.refClaim);
        writes.push({ path: p.refClaim, data: { type: entry.type, refId: entry.refId, entryId: entry.id, claimedAt: now } });
      }
      if (p.dayClaim !== undefined) {
        const n = (dayCounts.get(p.dayClaim) ?? 0) + 1;
        dayCounts.set(p.dayClaim, n);
        writes.push({ path: p.dayClaim, data: { type: entry.type, date: p.day ?? null, count: n, updatedAt: now } });
      }
    });

    if (wallet.needsSeed) tx.set(`${userPath}/ledger/${STARTING_WALLET_ENTRY_ID}`, startingWalletEntry(now));
    for (const w of writes) tx.set(w.path, w.data);
    tx.set(userPath, { ...walletUpdate(balance, now), lastLedgerSyncAt: now }, { merge: true });
    return { accepted, rejected, balance };
  });
}
