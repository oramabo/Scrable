/**
 * Server-granted rewards (coins + XP + season points) applied inside a
 * Firestore transaction: idempotent through the ledger entry id, capped per
 * UTC day through `users/{uid}/claims/{type}~day~{date}` counters (the same
 * marker scheme syncLedger uses for client earns).
 */
import type { ServerOnlyType } from '../economy';
import { type DocData, type DocSnapshot, readNumber, type Transaction } from './firestore';
import { seasonIdAt } from './season';
import { isoDate } from './time';
import { readWallet, STARTING_WALLET_ENTRY_ID, startingWalletEntry } from './wallet';

export type RewardType = Extract<ServerOnlyType, 'earn_match' | 'earn_coop'>;

export interface RewardGrant {
  /** Ledger entry id, e.g. `match_{matchId}_{uid}`; the grant is applied at most once per id. */
  entryId: string;
  type: RewardType;
  coins: number;
  xp: number;
  seasonPoints: number;
  /** What the entry refers to (match or room id). */
  refId: string;
  /** Rewarded grants of this type per player per UTC day. */
  perDay: number;
}

export interface RewardReads {
  user: DocSnapshot;
  entry: DocSnapshot;
  dayClaim: DocSnapshot;
}

export interface RewardOutcome {
  /** False when the entry already existed (replay) or the daily cap was reached. */
  credited: boolean;
  /** True when this call hit the cap (the entry is stored as rejected so replays stay idempotent). */
  capped: boolean;
  coins: number;
  xp: number;
  seasonPoints: number;
  seasonId: string | null;
}

export function rewardLedgerPath(uid: string, entryId: string): string {
  return `users/${uid}/ledger/${entryId}`;
}
export function rewardDayClaimPath(uid: string, type: RewardType, now: number): string {
  return `users/${uid}/claims/${type}~day~${isoDate(now)}`;
}

/** All reads a grant needs; call before the first write of the transaction. */
export async function readRewardState(tx: Transaction, uid: string, grant: RewardGrant, now: number): Promise<RewardReads> {
  const [user, entry, dayClaim] = await Promise.all([
    tx.get(`users/${uid}`),
    tx.get(rewardLedgerPath(uid, grant.entryId)),
    tx.get(rewardDayClaimPath(uid, grant.type, now)),
  ]);
  return { user, entry, dayClaim };
}

/**
 * Writes the ledger entry, the day counter and returns the patch to merge into
 * `users/{uid}` (wallet / xp / season). The caller merges that patch (together
 * with its own fields, e.g. trophies) in a single set so the user document is
 * written once per transaction.
 */
export function applyReward(tx: Transaction, uid: string, reads: RewardReads, grant: RewardGrant, now: number): { outcome: RewardOutcome; userPatch: DocData } {
  const seasonId = seasonIdAt(now) ?? null;
  const none: RewardOutcome = { credited: false, capped: false, coins: 0, xp: 0, seasonPoints: 0, seasonId };
  if (reads.entry.exists) return { outcome: none, userPatch: {} };

  const wallet = readWallet(reads.user);
  const userPath = `users/${uid}`;
  if (wallet.needsSeed) tx.set(`${userPath}/ledger/${STARTING_WALLET_ENTRY_ID}`, startingWalletEntry(now));

  const dayCount = readNumber(reads.dayClaim.data, 'count', 0);
  const base = { id: grant.entryId, type: grant.type, createdAt: now, deviceId: 'server', refId: grant.refId };
  if (dayCount >= grant.perDay) {
    const reason = `daily cap of ${grant.perDay} ${grant.type} rewards reached for ${isoDate(now)}`;
    tx.set(rewardLedgerPath(uid, grant.entryId), {
      ...base,
      amount: grant.coins,
      balanceAfter: wallet.balance,
      server: { status: 'rejected', source: 'server', reason, syncedAt: now, appliedAmount: 0 },
    });
    const patch: DocData = wallet.needsSeed ? { wallet: { balance: wallet.balance, updatedAt: now } } : {};
    return { outcome: { ...none, capped: true }, userPatch: patch };
  }

  const balance = wallet.balance + grant.coins;
  tx.set(rewardLedgerPath(uid, grant.entryId), {
    ...base,
    amount: grant.coins,
    balanceAfter: balance,
    server: { status: 'accepted', source: 'server', syncedAt: now, appliedAmount: grant.coins, xp: grant.xp, seasonPoints: grant.seasonPoints, seasonId },
  });
  tx.set(rewardDayClaimPath(uid, grant.type, now), { type: grant.type, date: isoDate(now), count: dayCount + 1, updatedAt: now });

  const userPatch: DocData = {
    wallet: { balance, updatedAt: now },
    xp: readNumber(reads.user.data, 'xp', 0) + grant.xp,
  };
  const seasonPoints = seasonId === null ? 0 : grant.seasonPoints;
  if (seasonId !== null && seasonPoints > 0) {
    userPatch['season'] = { [seasonId]: { points: readNumber(reads.user.data, `season.${seasonId}.points`, 0) + seasonPoints, updatedAt: now } };
  }
  return { outcome: { credited: true, capped: false, coins: grant.coins, xp: grant.xp, seasonPoints, seasonId }, userPatch };
}
