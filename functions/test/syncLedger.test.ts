import { EARN_RULES, MAX_ENTRIES_PER_SYNC, STARTING_WALLET } from '../src/economy';
import { syncLedger } from '../src/handlers/syncLedger';
import { DAY_MS } from '../src/lib/time';
import { FakeFirestore } from './fakeFirestore';
import { entry, NOW, resetSeq, uuid7 } from './helpers';

const UID = 'u1';

beforeEach(() => resetSeq());

describe('syncLedger', () => {
  test('accepts a valid earn, seeds the starting wallet and records the claim', async () => {
    const db = new FakeFirestore();
    const e = entry('earn_complete', 30, { refId: 'he-l1-001-01', lang: 'he' });
    const res = await syncLedger(db, UID, { entries: [e] }, NOW);
    expect(res).toEqual({ accepted: [e['id']], rejected: [], balance: STARTING_WALLET + 30 });
    expect(db.get(`users/${UID}/ledger/starting_wallet`)).toMatchObject({ type: 'admin_adjust', amount: STARTING_WALLET });
    expect(db.get(`users/${UID}/ledger/${e['id'] as string}`)).toMatchObject({ type: 'earn_complete', amount: 30, balanceAfter: STARTING_WALLET + 30, lang: 'he', server: { status: 'accepted', appliedAmount: 30 } });
    expect(db.get(`users/${UID}`)).toMatchObject({ wallet: { balance: STARTING_WALLET + 30 } });
    expect(db.list(`users/${UID}/claims`)).toEqual([`users/${UID}/claims/earn_complete~he-l1-001-01`]);
  });

  test('enforces the earn_complete cap and the once-per-puzzle rule', async () => {
    const db = new FakeFirestore();
    const tooMuch = entry('earn_complete', EARN_RULES.earn_complete.max + 1, { refId: 'p2' });
    const ok = entry('earn_complete', 120, { refId: 'p1' });
    const sameRefSameRequest = entry('earn_complete', 20, { refId: 'p1' });
    const noRef = entry('earn_complete', 20);
    const res = await syncLedger(db, UID, { entries: [tooMuch, ok, sameRefSameRequest, noRef] }, NOW);
    expect(res.accepted).toEqual([ok['id']]);
    expect(res.rejected).toHaveLength(3);
    expect(res.rejected.find((r) => r.id === tooMuch['id'])?.reason).toMatch(/cap of 120/);
    expect(res.rejected.find((r) => r.id === sameRefSameRequest['id'])?.reason).toMatch(/already credited/);
    expect(res.rejected.find((r) => r.id === noRef['id'])?.reason).toMatch(/requires a refId/);
    expect(res.balance).toBe(STARTING_WALLET + 120);

    const later = entry('earn_complete', 50, { refId: 'p1' });
    const res2 = await syncLedger(db, UID, { entries: [later] }, NOW + 1000);
    expect(res2.accepted).toEqual([]);
    expect(res2.rejected[0]?.reason).toMatch(/already credited for p1/);
    expect(res2.balance).toBe(STARTING_WALLET + 120);
    expect(db.get(`users/${UID}/ledger/${later['id'] as string}`)).toMatchObject({ server: { status: 'rejected' } });
  });

  test('enforces the earn_ad amount cap and daily cap', async () => {
    const db = new FakeFirestore();
    const ads = Array.from({ length: 7 }, (_, i) => entry('earn_ad', 25, { refId: `ad-${i}` }));
    const res = await syncLedger(db, UID, { entries: ads }, NOW);
    expect(res.accepted).toHaveLength(6);
    expect(res.rejected).toHaveLength(1);
    expect(res.rejected[0]?.reason).toMatch(/daily cap of 6/);
    expect(res.balance).toBe(STARTING_WALLET + 6 * 25);

    const nextDay = entry('earn_ad', 25, { createdAt: NOW + DAY_MS, refId: 'ad-8' });
    const big = entry('earn_ad', 31, { createdAt: NOW + DAY_MS, refId: 'ad-9' });
    const res2 = await syncLedger(db, UID, { entries: [nextDay, big] }, NOW + DAY_MS + 1000);
    expect(res2.accepted).toEqual([nextDay['id']]);
    expect(res2.rejected[0]?.reason).toMatch(/cap of 30/);
  });

  test('rejects spends that would take the balance below zero', async () => {
    const db = new FakeFirestore();
    const tooBig = entry('spend_item', -500, { refId: 'theme_gold', createdAt: NOW - 5000 });
    const letter = entry('spend_letter', -15, { refId: 'revealLetter', createdAt: NOW - 4000 });
    const res = await syncLedger(db, UID, { entries: [tooBig, letter] }, NOW);
    expect(res.accepted).toEqual([letter['id']]);
    expect(res.rejected).toEqual([{ id: tooBig['id'], reason: expect.stringMatching(/insufficient balance/) }]);
    expect(res.balance).toBe(STARTING_WALLET - 15);

    const exact = entry('spend_item', -(STARTING_WALLET - 15), { refId: 'archive', createdAt: NOW - 3000 });
    const oneMore = entry('spend_check', -5, { refId: 'checkWord', createdAt: NOW - 2000 });
    const res2 = await syncLedger(db, UID, { entries: [exact, oneMore] }, NOW);
    expect(res2.accepted).toEqual([exact['id']]);
    expect(res2.rejected[0]?.reason).toMatch(/insufficient balance/);
    expect(res2.balance).toBe(0);
  });

  test('rejects positive spends, over-priced spends and server-only types', async () => {
    const db = new FakeFirestore();
    const positive = entry('spend_letter', 15);
    const overPriced = entry('spend_letter', -25);
    const purchase = entry('purchase_bundle', 300, { refId: 'coins_300' });
    const refund = entry('refund', -300);
    const admin = entry('admin_adjust', 5000);
    const negativeEarn = entry('earn_login', -10);
    const res = await syncLedger(db, UID, { entries: [positive, overPriced, purchase, refund, admin, negativeEarn] }, NOW);
    expect(res.accepted).toEqual([]);
    const reasons = Object.fromEntries(res.rejected.map((r) => [r.id, r.reason]));
    expect(reasons[positive['id'] as string]).toMatch(/negative/);
    expect(reasons[overPriced['id'] as string]).toMatch(/price cap of 20/);
    expect(reasons[purchase['id'] as string]).toMatch(/server/);
    expect(reasons[refund['id'] as string]).toMatch(/server/);
    expect(reasons[admin['id'] as string]).toMatch(/server/);
    expect(reasons[negativeEarn['id'] as string]).toMatch(/positive/);
    expect(res.balance).toBe(STARTING_WALLET);
  });

  test('is idempotent: replaying accepted and rejected entries changes nothing', async () => {
    const db = new FakeFirestore();
    const ok = entry('earn_login', 10, { refId: 'login' });
    const bad = entry('earn_login', 60, { refId: 'login' });
    const first = await syncLedger(db, UID, { entries: [ok, bad] }, NOW);
    expect(first.accepted).toEqual([ok['id']]);
    const ledgerBefore = db.list(`users/${UID}/ledger`);
    const replay = await syncLedger(db, UID, { entries: [ok, bad] }, NOW + 10_000);
    expect(replay.accepted).toEqual([ok['id']]);
    expect(replay.rejected).toEqual(first.rejected);
    expect(replay.balance).toBe(STARTING_WALLET + 10);
    expect(db.list(`users/${UID}/ledger`)).toEqual(ledgerBefore);
  });

  test('rejects entries that fail the JSON schema and stores them as rejected', async () => {
    const db = new FakeFirestore();
    const badId = entry('earn_login', 10, { id: 'not-a-uuid' });
    const missingDevice = entry('earn_login', 10);
    delete missingDevice['deviceId'];
    const fraction = entry('earn_login', 9.5);
    const unknownType = entry('earn_bonus', 10);
    const withServer: Record<string, unknown> = { ...entry('earn_login', 10), server: { status: 'accepted' } };
    const res = await syncLedger(db, UID, { entries: [badId, missingDevice, fraction, unknownType, withServer] }, NOW);
    expect(res.accepted).toEqual([]);
    expect(res.rejected).toHaveLength(5);
    for (const r of res.rejected.filter((x) => x.id !== withServer['id'])) expect(r.reason).toMatch(/^schema:/);
    expect(res.rejected.find((r) => r.id === withServer['id'])?.reason).toMatch(/reserved/);
    expect(db.get(`users/${UID}/ledger/not-a-uuid`)).toMatchObject({ server: { status: 'rejected' } });
  });

  test('throws invalid-argument for malformed requests', async () => {
    const db = new FakeFirestore();
    await expect(syncLedger(db, UID, {}, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(syncLedger(db, UID, { entries: 'x' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(syncLedger(db, UID, { entries: [] }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(syncLedger(db, UID, { entries: [{ type: 'earn_login' }] }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    const tooMany = Array.from({ length: MAX_ENTRIES_PER_SYNC + 1 }, () => entry('earn_login', 1));
    await expect(syncLedger(db, UID, { entries: tooMany }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    expect(db.writeCount).toBe(0);
  });

  test('stores reconcile entries without moving coins and flags duplicates within a request', async () => {
    const db = new FakeFirestore();
    const rec = entry('reconcile', -37);
    const dup = entry('earn_login', 10, { id: uuid7(99), refId: 'login' });
    const res = await syncLedger(db, UID, { entries: [rec, dup, { ...dup }] }, NOW);
    expect(res.accepted).toEqual(expect.arrayContaining([rec['id'], dup['id']]));
    expect(res.rejected).toEqual([{ id: dup['id'], reason: 'duplicate id within the request' }]);
    expect(res.balance).toBe(STARTING_WALLET + 10);
    expect(db.get(`users/${UID}/ledger/${rec['id'] as string}`)).toMatchObject({ amount: -37, server: { appliedAmount: 0 } });
  });

  test('rejects stale and future-dated entries', async () => {
    const db = new FakeFirestore();
    const stale = entry('earn_login', 10, { createdAt: NOW - 8 * DAY_MS, refId: 'login' });
    const future = entry('earn_login', 10, { createdAt: NOW + 3_600_000, refId: 'login' });
    const res = await syncLedger(db, UID, { entries: [stale, future] }, NOW);
    expect(res.accepted).toEqual([]);
    expect(res.rejected.map((r) => r.reason).sort()).toEqual([expect.stringMatching(/future/), expect.stringMatching(/older than 7 days/)]);
  });
});
