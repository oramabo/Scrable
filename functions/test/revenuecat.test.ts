import { STARTING_WALLET } from '../src/economy';
import { handleRevenueCatWebhook } from '../src/handlers/revenuecat';
import { FakeFirestore } from './fakeFirestore';
import { NOW } from './helpers';

const SECRET = 'rc-test-secret';

function body(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    api_version: '1.0',
    event: {
      id: 'evt-1',
      type: 'INITIAL_PURCHASE',
      app_user_id: 'user1',
      product_id: 'coins_800',
      price: 19.9,
      currency: 'ILS',
      entitlement_ids: [],
      event_timestamp_ms: NOW - 1000,
      store: 'APP_STORE',
      environment: 'SANDBOX',
      ...overrides,
    },
  };
}

/** `authorization: null` sends no Authorization header at all. */
function request(payload: unknown, authorization: string | null = `Bearer ${SECRET}`, method = 'POST') {
  return { method, headers: authorization === null ? {} : { authorization }, body: payload };
}

describe('revenuecatWebhook', () => {
  test('rejects a missing or wrong secret with 401 and touches nothing', async () => {
    const db = new FakeFirestore();
    expect((await handleRevenueCatWebhook(db, SECRET, request(body(), null), NOW)).status).toBe(401);
    expect((await handleRevenueCatWebhook(db, SECRET, request(body(), 'Bearer nope'), NOW)).status).toBe(401);
    expect((await handleRevenueCatWebhook(db, SECRET, request(body(), `Basic ${SECRET}`), NOW)).status).toBe(401);
    expect((await handleRevenueCatWebhook(db, undefined, request(body()), NOW)).status).toBe(401);
    expect(db.writeCount).toBe(0);
  });

  test('rejects malformed bodies with 400', async () => {
    const db = new FakeFirestore();
    expect((await handleRevenueCatWebhook(db, SECRET, request({}), NOW)).status).toBe(400);
    expect((await handleRevenueCatWebhook(db, SECRET, request('text'), NOW)).status).toBe(400);
    expect((await handleRevenueCatWebhook(db, SECRET, request({ event: { type: 'INITIAL_PURCHASE' } }), NOW)).status).toBe(400);
    expect((await handleRevenueCatWebhook(db, SECRET, request({ event: { id: 'x', type: 'INITIAL_PURCHASE' } }), NOW)).status).toBe(400);
    expect(db.writeCount).toBe(0);
  });

  test('answers 405 to non-POST requests', async () => {
    const db = new FakeFirestore();
    expect((await handleRevenueCatWebhook(db, SECRET, request(body(), `Bearer ${SECRET}`, 'GET'), NOW)).status).toBe(405);
  });

  test('credits a coin bundle once, even when the same event is delivered twice', async () => {
    const db = new FakeFirestore();
    const first = await handleRevenueCatWebhook(db, SECRET, request(body()), NOW);
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ ok: true, status: 'credited', uid: 'user1', amount: 800, balance: STARTING_WALLET + 800 });
    const entry = db.get('users/user1/ledger/rc_evt-1');
    expect(entry).toMatchObject({ id: 'rc_evt-1', type: 'purchase_bundle', amount: 800, balanceAfter: STARTING_WALLET + 800, refId: 'coins_800', deviceId: 'server:revenuecat' });
    expect(entry?.['server']).toMatchObject({ status: 'accepted', source: 'revenuecat', eventId: 'evt-1' });
    expect(db.get('users/user1/ledger/starting_wallet')).toMatchObject({ amount: STARTING_WALLET });
    expect(db.get('users/user1')).toMatchObject({ wallet: { balance: STARTING_WALLET + 800 } });

    const writesBefore = db.writeCount;
    const second = await handleRevenueCatWebhook(db, SECRET, request(body()), NOW + 5000);
    expect(second.status).toBe(200);
    expect(second.body).toMatchObject({ status: 'duplicate' });
    expect(db.writeCount).toBe(writesBefore);
    expect(db.get('users/user1')).toMatchObject({ wallet: { balance: STARTING_WALLET + 800 } });
    expect(db.list('users/user1/ledger')).toEqual(['users/user1/ledger/rc_evt-1', 'users/user1/ledger/starting_wallet']);
  });

  test('credits RENEWAL and NON_RENEWING_PURCHASE of coin products and ignores unknown products', async () => {
    const db = new FakeFirestore();
    await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'a', type: 'NON_RENEWING_PURCHASE', product_id: 'coins_300' })), NOW);
    await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'b', type: 'RENEWAL', product_id: 'coins_2000' })), NOW);
    const ignored = await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'c', product_id: 'mystery_box' })), NOW);
    expect(ignored.body).toMatchObject({ status: 'ignored' });
    expect(db.get('users/user1')).toMatchObject({ wallet: { balance: STARTING_WALLET + 300 + 2000 } });
  });

  test('writes a negative refund entry for a refunded consumable, exactly once', async () => {
    const db = new FakeFirestore();
    await handleRevenueCatWebhook(db, SECRET, request(body()), NOW);
    const refund = body({ id: 'evt-2', type: 'CANCELLATION', cancel_reason: 'CUSTOMER_SUPPORT' });
    const res = await handleRevenueCatWebhook(db, SECRET, request(refund), NOW);
    expect(res.body).toMatchObject({ status: 'refunded', amount: -800, balance: STARTING_WALLET });
    expect(db.get('users/user1/ledger/rc_evt-2_refund')).toMatchObject({ type: 'refund', amount: -800, balanceAfter: STARTING_WALLET });
    const again = await handleRevenueCatWebhook(db, SECRET, request(refund), NOW);
    expect(again.body).toMatchObject({ status: 'duplicate' });
    expect(db.get('users/user1')).toMatchObject({ wallet: { balance: STARTING_WALLET } });
  });

  test('mirrors entitlements for every event type and revokes them on expiration or refund', async () => {
    const db = new FakeFirestore();
    const premium = body({ id: 'p1', product_id: 'premium_monthly', entitlement_ids: ['premium'] });
    const res = await handleRevenueCatWebhook(db, SECRET, request(premium), NOW);
    expect(res.body).toMatchObject({ status: 'entitlements', entitlements: { premium: true } });
    expect(db.get('users/user1')).toMatchObject({ entitlements: { premium: true } });
    expect(db.list('users/user1/ledger')).toEqual([]); // subscriptions never move coins

    // auto-renew switched off: still active until expiration
    await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'p2', type: 'CANCELLATION', cancel_reason: 'UNSUBSCRIBE', product_id: 'premium_monthly', entitlement_ids: ['premium'] })), NOW);
    expect(db.get('users/user1')).toMatchObject({ entitlements: { premium: true } });

    await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'ra', product_id: 'remove_ads', entitlement_ids: ['remove_ads', 'unknown_ent'] })), NOW);
    expect(db.get('users/user1')).toMatchObject({ entitlements: { premium: true, remove_ads: true } });

    await handleRevenueCatWebhook(db, SECRET, request(body({ id: 'p3', type: 'EXPIRATION', product_id: 'premium_monthly', entitlement_ids: ['premium'] })), NOW);
    expect(db.get('users/user1')).toMatchObject({ entitlements: { premium: false, remove_ads: true }, entitlementsMeta: { lastEventId: 'p3' } });
  });

  test('ignores anonymous RevenueCat ids unless a Firebase uid alias is present', async () => {
    const db = new FakeFirestore();
    const anon = await handleRevenueCatWebhook(db, SECRET, request(body({ app_user_id: '$RCAnonymousID:abc' })), NOW);
    expect(anon.status).toBe(200);
    expect(anon.body).toMatchObject({ status: 'ignored' });
    expect(db.writeCount).toBe(0);
    const aliased = await handleRevenueCatWebhook(db, SECRET, request(body({ app_user_id: '$RCAnonymousID:abc', aliases: ['$RCAnonymousID:abc', 'realUid'] })), NOW);
    expect(aliased.body).toMatchObject({ status: 'credited', uid: 'realUid' });
  });
});
