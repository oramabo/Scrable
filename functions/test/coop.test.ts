import { COOP_REWARD_MIN_DURATION_MS, COOP_REWARDS, COOP_REWARDS_PER_DAY, STARTING_WALLET } from '../src/economy';
import {
  type CoopDeps,
  type CoopRoomDoc,
  coopLedgerEntryId,
  createCoopRoom,
  expireRooms,
  finishCoopRoom,
  joinCoopRoom,
  leaveCoopRoom,
  ROOM_IDLE_MS,
  roomPath,
  startCoopRoom,
} from '../src/handlers/coop';
import { inviteCodePath } from '../src/lib/ids';
import { puzzleIndexPath } from '../src/lib/puzzleLookup';
import { validate } from '../src/lib/validate';
import { FakeFirestore } from './fakeFirestore';
import { uuid7 } from './helpers';

const NOW = Date.UTC(2026, 10, 10, 12, 0, 0);
const HASH = 'e'.repeat(64);
const MIN = 60_000;

function lcg(seed = 7): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 2 ** 32;
  };
}

function seeded(extra: Record<string, Record<string, unknown>> = {}): { db: FakeFirestore; deps: CoopDeps } {
  const db = new FakeFirestore({
    'users/a': { profile: { displayName: 'Noa' }, wallet: { balance: 100, updatedAt: NOW } },
    'users/b': { profile: { displayName: 'Ben' } },
    [puzzleIndexPath('en-l1-p01-02')]: { puzzleId: 'en-l1-p01-02', lang: 'en', kind: 'pack', level: 1, letterCells: 48, solutionHash: HASH },
    ...extra,
  });
  return { db, deps: { db, random: lcg() } };
}

function room(db: FakeFirestore, roomId: string): CoopRoomDoc {
  return db.get(roomPath(roomId)) as unknown as CoopRoomDoc;
}

describe('co-op rooms', () => {
  test('create / join (5th member rejected, colours unique) / start / leave with host hand-over', async () => {
    const { db, deps } = seeded();
    const created = await createCoopRoom(deps, 'a', { lang: 'en', puzzleId: 'en-l1-p01-02' }, NOW);
    expect(created.code).toMatch(/^[A-Z0-9]{6}$/);
    expect(created.room).toMatchObject({ status: 'open', hostUid: 'a', letterCells: 48, solutionHash: HASH, code: created.code });
    expect(created.room.members['a']).toMatchObject({ displayName: 'Noa', color: 0, cursor: null });
    expect(db.get(inviteCodePath(created.code))).toMatchObject({ kind: 'coop', refId: created.roomId });
    expect(validate('coop-room', room(db, created.roomId))).toEqual({ ok: true, errors: [] });

    for (const [i, uid] of ['b', 'c', 'd'].entries()) {
      const joined = await joinCoopRoom(deps, uid, { code: created.code }, NOW + (i + 1) * 1000);
      expect(joined.room.members[uid]?.color).toBe(i + 1);
    }
    await expect(joinCoopRoom(deps, 'e', { code: created.code }, NOW + 5000)).rejects.toMatchObject({ code: 'failed-precondition' });
    // re-joining is idempotent
    expect(Object.keys((await joinCoopRoom(deps, 'b', { code: created.code }, NOW + 6000)).room.members)).toHaveLength(4);
    expect(validate('coop-room', room(db, created.roomId))).toEqual({ ok: true, errors: [] });

    await expect(startCoopRoom(deps, 'b', { roomId: created.roomId }, NOW + 7000)).rejects.toMatchObject({ code: 'permission-denied' });
    expect((await startCoopRoom(deps, 'a', { roomId: created.roomId }, NOW + 7000)).room).toMatchObject({ status: 'running', startedAt: NOW + 7000 });

    // the host leaves: the earliest remaining member becomes host; the freed colour is reused
    expect(await leaveCoopRoom(deps, 'a', { roomId: created.roomId }, NOW + 8000)).toEqual({ roomId: created.roomId, status: 'running', hostUid: 'b' });
    expect((await joinCoopRoom(deps, 'e', { code: created.code }, NOW + 9000)).room.members['e']?.color).toBe(0);
    await expect(joinCoopRoom(deps, 'z', { code: 'nope!!' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(joinCoopRoom(deps, 'z', { code: 'ZZZZZZ' }, NOW)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('finish: host only, hash checked, every member rewarded once (coins + XP), replay idempotent', async () => {
    const { db, deps } = seeded();
    const created = await createCoopRoom(deps, 'a', { lang: 'en', puzzleId: 'en-l1-p01-02' }, NOW);
    await joinCoopRoom(deps, 'b', { code: created.code }, NOW + MIN);
    const t = NOW + 10 * MIN;
    await expect(finishCoopRoom(deps, 'b', { roomId: created.roomId, solutionHash: HASH }, t)).rejects.toMatchObject({ code: 'permission-denied' });
    await expect(finishCoopRoom(deps, 'a', { roomId: created.roomId, solutionHash: 'f'.repeat(64) }, t)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(finishCoopRoom(deps, 'a', { roomId: created.roomId }, t)).rejects.toMatchObject({ code: 'invalid-argument' });

    const finished = await finishCoopRoom(deps, 'a', { roomId: created.roomId, solutionHash: HASH }, t);
    expect(finished).toMatchObject({ status: 'finished', rewarded: true });
    expect(finished.members['a']).toEqual({ credited: true, capped: false, coins: 25, xp: 30, seasonPoints: 0, seasonId: '2026-S1' });
    expect(finished.members['b']).toMatchObject({ credited: true, coins: 25, xp: 30 });
    const r = room(db, created.roomId);
    expect(r).toMatchObject({ status: 'finished', finishReason: 'solved', finishedAt: t });
    expect(validate('coop-room', r)).toEqual({ ok: true, errors: [] });
    expect(db.get(inviteCodePath(created.code))).toBeUndefined();
    expect(db.get('users/a')).toMatchObject({ xp: 30, wallet: { balance: 125 } });
    expect(db.get('users/a')?.['season']).toBeUndefined(); // co-op pays no season points
    expect(db.get('users/b')).toMatchObject({ xp: 30, wallet: { balance: STARTING_WALLET + 25 } });
    const entry = db.get(`users/b/ledger/${coopLedgerEntryId(created.roomId, 'b')}`);
    expect(entry).toMatchObject({ type: 'earn_coop', amount: COOP_REWARDS.coins, refId: created.roomId, server: { status: 'accepted', xp: COOP_REWARDS.xp } });
    expect(validate('ledger-entry', { ...entry, id: uuid7(1) })).toEqual({ ok: true, errors: [] });
    expect(db.get('users/b/claims/earn_coop~day~2026-11-10')).toMatchObject({ count: 1 });

    const writes = db.writeCount;
    const replay = await finishCoopRoom(deps, 'a', { roomId: created.roomId, solutionHash: HASH }, t + MIN);
    expect(replay).toMatchObject({ status: 'finished', rewarded: true });
    expect(replay.members['a']).toMatchObject({ credited: true, coins: 25 });
    expect(db.writeCount).toBe(writes);
    expect(db.get('users/a')).toMatchObject({ xp: 30, wallet: { balance: 125 } });
    // joining a finished room is refused
    await expect(joinCoopRoom(deps, 'c', { code: created.code }, t + MIN)).rejects.toMatchObject({ code: 'not-found' });
  });

  test('anti-farming: solo rooms, rooms younger than a minute and the daily cap pay nothing', async () => {
    const { db, deps } = seeded({ 'users/b/claims/earn_coop~day~2026-11-10': { count: COOP_REWARDS_PER_DAY } });
    const solo = await createCoopRoom(deps, 'a', { lang: 'en', puzzleId: 'en-l1-p01-02' }, NOW);
    expect(await finishCoopRoom(deps, 'a', { roomId: solo.roomId, solutionHash: HASH }, NOW + 5 * MIN)).toMatchObject({ rewarded: false, members: {} });
    expect(db.get('users/a')).toMatchObject({ wallet: { balance: 100 } });

    const quick = await createCoopRoom(deps, 'a', { lang: 'en', puzzleId: 'en-l1-p01-02' }, NOW);
    await joinCoopRoom(deps, 'b', { code: quick.code }, NOW + 1000);
    expect((await finishCoopRoom(deps, 'a', { roomId: quick.roomId, solutionHash: HASH }, NOW + COOP_REWARD_MIN_DURATION_MS - 1)).rewarded).toBe(false);

    const capped = await createCoopRoom(deps, 'a', { lang: 'en', puzzleId: 'en-l1-p01-02' }, NOW);
    await joinCoopRoom(deps, 'b', { code: capped.code }, NOW + 1000);
    const done = await finishCoopRoom(deps, 'a', { roomId: capped.roomId, solutionHash: HASH }, NOW + 2 * MIN);
    expect(done.rewarded).toBe(true);
    expect(done.members['a']).toMatchObject({ credited: true, coins: 25 });
    expect(done.members['b']).toMatchObject({ credited: false, capped: true, coins: 0 });
    expect(db.get('users/b')?.['xp']).toBeUndefined();
  });

  test('unknown puzzles are accepted without a hash; expireRooms closes rooms idle for two hours and an emptied room is abandoned', async () => {
    const { db, deps } = seeded();
    const created = await createCoopRoom(deps, 'a', { lang: 'he', puzzleId: 'he-l9-p99-01' }, NOW);
    expect(created.room).toMatchObject({ letterCells: null, solutionHash: null });
    await joinCoopRoom(deps, 'b', { code: created.code }, NOW + MIN);
    // a member heartbeat (written by the client under the rules) keeps the room alive
    await db.setDoc(roomPath(created.roomId), { members: { b: { lastSeenAt: NOW + 90 * MIN } } }, { merge: true });
    expect(await expireRooms(deps, NOW + MIN + ROOM_IDLE_MS)).toEqual({ scanned: 1, expired: 0 });
    const result = await expireRooms(deps, NOW + 90 * MIN + ROOM_IDLE_MS);
    expect(result).toEqual({ scanned: 1, expired: 1 });
    expect(room(db, created.roomId)).toMatchObject({ status: 'finished', finishReason: 'expired' });
    expect(db.get(inviteCodePath(created.code))).toBeUndefined();

    const other = await createCoopRoom(deps, 'a', { lang: 'he', puzzleId: 'he-l9-p99-01' }, NOW);
    expect((await finishCoopRoom(deps, 'a', { roomId: other.roomId }, NOW + MIN)).status).toBe('finished'); // no hash known → host's word
    const third = await createCoopRoom(deps, 'a', { lang: 'he', puzzleId: 'he-l9-p99-01' }, NOW);
    expect(await leaveCoopRoom(deps, 'a', { roomId: third.roomId }, NOW + MIN)).toMatchObject({ status: 'finished' });
    expect(room(db, third.roomId)).toMatchObject({ finishReason: 'abandoned', members: {} });
    expect(validate('coop-room', room(db, third.roomId))).toEqual({ ok: true, errors: [] });
  });
});
