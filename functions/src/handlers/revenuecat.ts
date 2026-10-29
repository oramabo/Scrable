/**
 * RevenueCat webhook: credits coin bundles idempotently (`rc_{eventId}`),
 * debits refunded consumables (`rc_{eventId}_refund`) and mirrors
 * entitlements to `users/{uid}.entitlements`.
 * https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
 */
import { COIN_PRODUCTS, isEntitlementId } from '../economy';
import { bearerToken, secretsEqual } from '../lib/auth';
import type { Db, DocData } from '../lib/firestore';
import { readWallet, STARTING_WALLET_ENTRY_ID, startingWalletEntry, walletUpdate } from '../lib/wallet';

export class WebhookBadRequest extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WebhookBadRequest';
  }
}

export interface RevenueCatEvent {
  id: string;
  type: string;
  appUserId: string;
  aliases: string[];
  productId: string | undefined;
  price: number | undefined;
  currency: string | undefined;
  entitlementIds: string[];
  cancelReason: string | undefined;
  expirationReason: string | undefined;
  eventTimestampMs: number | undefined;
  store: string | undefined;
  environment: string | undefined;
}

const EVENT_ID = /^[A-Za-z0-9_.:-]{1,120}$/;

function optionalString(v: unknown): string | undefined {
  return typeof v === 'string' ? v : undefined;
}
function optionalNumber(v: unknown): number | undefined {
  return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
}
function stringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
}

/** Extracts the fields the backend uses from a webhook body; throws WebhookBadRequest on malformed input. */
export function parseRevenueCatBody(body: unknown): RevenueCatEvent {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) throw new WebhookBadRequest('body must be a JSON object');
  const event = (body as { event?: unknown }).event;
  if (typeof event !== 'object' || event === null || Array.isArray(event)) throw new WebhookBadRequest('missing `event` object');
  const e = event as Record<string, unknown>;
  const id = e['id'];
  const type = e['type'];
  const appUserId = e['app_user_id'];
  if (typeof id !== 'string' || !EVENT_ID.test(id)) throw new WebhookBadRequest('`event.id` must be a short identifier string');
  if (typeof type !== 'string' || type.length === 0 || type.length > 64) throw new WebhookBadRequest('`event.type` must be a string');
  if (typeof appUserId !== 'string' || appUserId.length === 0) throw new WebhookBadRequest('`event.app_user_id` must be a string');
  return {
    id,
    type,
    appUserId,
    aliases: stringArray(e['aliases']),
    productId: optionalString(e['product_id']),
    price: optionalNumber(e['price']),
    currency: optionalString(e['currency']),
    entitlementIds: stringArray(e['entitlement_ids']),
    cancelReason: optionalString(e['cancel_reason']),
    expirationReason: optionalString(e['expiration_reason']),
    eventTimestampMs: optionalNumber(e['event_timestamp_ms']),
    store: optionalString(e['store']),
    environment: optionalString(e['environment']),
  };
}

const ANONYMOUS_PREFIX = '$RCAnonymousID:';
const FIREBASE_UID = /^[A-Za-z0-9_-]{1,128}$/;

/** The Firebase uid: the app user id, or the first non-anonymous alias. */
export function resolveUid(event: RevenueCatEvent): string | undefined {
  return [event.appUserId, ...event.aliases].find((c) => !c.startsWith(ANONYMOUS_PREFIX) && FIREBASE_UID.test(c));
}

export const PURCHASE_EVENT_TYPES: ReadonlySet<string> = new Set(['INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL']);

/** A CANCELLATION of a consumable is a refund; an EXPIRATION by customer support is a revoked (refunded) purchase. */
export function isRefundEvent(event: RevenueCatEvent): boolean {
  if (event.type === 'CANCELLATION') return (event.cancelReason ?? 'CUSTOMER_SUPPORT') === 'CUSTOMER_SUPPORT';
  if (event.type === 'EXPIRATION') return event.expirationReason === 'CUSTOMER_SUPPORT';
  return false;
}

export type WebhookStatus = 'credited' | 'refunded' | 'duplicate' | 'entitlements' | 'ignored';

export interface WebhookOutcome {
  status: WebhookStatus;
  uid?: string;
  amount?: number;
  balance?: number;
  entitlements?: Record<string, boolean>;
  reason?: string;
}

interface CoinMove {
  entryId: string;
  type: 'purchase_bundle' | 'refund';
  amount: number;
  status: 'credited' | 'refunded';
}

async function mirrorEntitlements(db: Db, uid: string, event: RevenueCatEvent, now: number): Promise<Record<string, boolean> | undefined> {
  const known = event.entitlementIds.filter(isEntitlementId);
  if (known.length === 0) return undefined;
  // EXPIRATION and refunds revoke access; every other event (purchase, renewal, cancellation of auto-renew, ...) leaves it active.
  const active = !(event.type === 'EXPIRATION' || (event.type === 'CANCELLATION' && isRefundEvent(event)));
  const flags: Record<string, boolean> = {};
  for (const id of known) flags[id] = active;
  await db.setDoc(
    `users/${uid}`,
    { entitlements: flags, entitlementsMeta: { updatedAt: now, source: 'revenuecat', lastEventId: event.id, lastEventType: event.type } },
    { merge: true },
  );
  return flags;
}

async function applyCoinMove(db: Db, uid: string, event: RevenueCatEvent, move: CoinMove, now: number, entitlements: Record<string, boolean> | undefined): Promise<WebhookOutcome> {
  const userPath = `users/${uid}`;
  const entryPath = `${userPath}/ledger/${move.entryId}`;
  return db.runTransaction(async (tx) => {
    const [user, entry] = await Promise.all([tx.get(userPath), tx.get(entryPath)]);
    if (entry.exists) {
      return { status: 'duplicate', uid, amount: 0, entitlements, reason: `ledger entry ${move.entryId} already exists` };
    }
    const wallet = readWallet(user);
    const balance = wallet.balance + move.amount;
    const ledgerEntry: DocData = {
      id: move.entryId,
      type: move.type,
      amount: move.amount,
      balanceAfter: balance,
      createdAt: event.eventTimestampMs ?? now,
      deviceId: 'server:revenuecat',
      refId: event.productId ?? null,
      server: {
        status: 'accepted',
        source: 'revenuecat',
        syncedAt: now,
        appliedAmount: move.amount,
        eventId: event.id,
        eventType: event.type,
        price: event.price ?? null,
        currency: event.currency ?? null,
        store: event.store ?? null,
        environment: event.environment ?? null,
      },
    };
    if (wallet.needsSeed) tx.set(`${userPath}/ledger/${STARTING_WALLET_ENTRY_ID}`, startingWalletEntry(now));
    tx.set(entryPath, ledgerEntry);
    tx.set(userPath, walletUpdate(balance, now), { merge: true });
    return { status: move.status, uid, amount: move.amount, balance, entitlements };
  });
}

/** Applies one parsed webhook event. Safe to call repeatedly with the same event. */
export async function processRevenueCatEvent(db: Db, event: RevenueCatEvent, now: number): Promise<WebhookOutcome> {
  const uid = resolveUid(event);
  if (uid === undefined) return { status: 'ignored', reason: 'anonymous app_user_id without a Firebase uid alias' };
  const entitlements = await mirrorEntitlements(db, uid, event, now);
  const coins = event.productId !== undefined ? COIN_PRODUCTS[event.productId] : undefined;
  if (coins === undefined) {
    return entitlements
      ? { status: 'entitlements', uid, entitlements }
      : { status: 'ignored', uid, reason: `product ${event.productId ?? '(none)'} is not a coin bundle` };
  }
  if (PURCHASE_EVENT_TYPES.has(event.type)) {
    return applyCoinMove(db, uid, event, { entryId: `rc_${event.id}`, type: 'purchase_bundle', amount: coins, status: 'credited' }, now, entitlements);
  }
  if (isRefundEvent(event)) {
    return applyCoinMove(db, uid, event, { entryId: `rc_${event.id}_refund`, type: 'refund', amount: -coins, status: 'refunded' }, now, entitlements);
  }
  return { status: 'ignored', uid, entitlements, reason: `event type ${event.type} does not move coins` };
}

export interface WebhookHttpRequest {
  method: string;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
}

export interface WebhookHttpResponse {
  status: number;
  body: Record<string, unknown>;
}

/** Transport-level handler: 405 non-POST, 401 bad secret, 400 malformed body, 200 after processing. */
export async function handleRevenueCatWebhook(db: Db, secret: string | undefined, req: WebhookHttpRequest, now: number): Promise<WebhookHttpResponse> {
  if (req.method !== 'POST') return { status: 405, body: { error: 'method not allowed' } };
  if (!secretsEqual(bearerToken(req.headers['authorization']), secret)) return { status: 401, body: { error: 'unauthorized' } };
  let event: RevenueCatEvent;
  try {
    event = parseRevenueCatBody(req.body);
  } catch (err) {
    if (err instanceof WebhookBadRequest) return { status: 400, body: { error: err.message } };
    throw err;
  }
  const outcome = await processRevenueCatEvent(db, event, now);
  return { status: 200, body: { ok: true, eventId: event.id, eventType: event.type, ...outcome } };
}
