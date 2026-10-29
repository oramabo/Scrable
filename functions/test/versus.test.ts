import { MATCH_REWARDS, MATCH_REWARDS_PER_DAY, STARTING_WALLET } from '../src/economy';
import { trophyLeaderboard } from '../src/handlers/trophyLeaderboard';
import {
  cancelMatch,
  createMatch,
  ELAPSED_TOLERANCE,
  expireMatches,
  findMatch,
  finishMatch,
  joinMatch,
  leaveMatch,
  MATCH_TIMEOUTS,
  type MatchDoc,
  matchLedgerEntryId,
  matchPath,
  queueEntriesPath,
  reportProgress,
  startMatch,
  trophyBoardEntryPath,
  type VersusDeps,
} from '../src/handlers/versus';
import { inviteCodePath } from '../src/lib/ids';
import { matchPoolPath } from '../src/lib/puzzleLookup';
import { validate } from '../src/lib/validate';
import { FakeFirestore } from './fakeFirestore';
import { uuid7 } from './helpers';

/** 2026-11-10T12:00:00Z — inside season 2026-S1. */
const NOW = Date.UTC(2026, 10, 10, 12, 0, 0);
const HASH = 'c'.repeat(64);
const OTHER_HASH = 'd'.repeat(64);
const MIN = 60_000;

/** Deterministic LCG so invite codes and ids are reproducible. */
function lcg(seed = 42): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 2 ** 32;
  };
}

function seeded(extra: Record<string, Record<string, unknown>> = {}): { db: FakeFirestore; deps: VersusDeps } {
  const db = new FakeFirestore({
    'users/host': { profile: { displayName: 'דנה' }, trophies: 120, wallet: { balance: 500, updatedAt: NOW - MIN } },
    'users/guest': { profile: { displayName: 'Ben' }, trophies: 160 },
    [matchPoolPath('he', 2)]: { puzzles: [{ puzzleId: 'he-l2-p01-03', letterCells: 64, solutionHash: HASH }] },
    'dailies/he_2026-11-09_easy': { puzzleId: 'he-d-2026-11-09-easy', lang: 'he', level: 1, letterCells: 40, solutionHash: OTHER_HASH },
    ...extra,
  });
  return { db, deps: { db, random: lcg() } };
}

function match(db: FakeFirestore, matchId: string): MatchDoc {
  return db.get(matchPath(matchId)) as unknown as MatchDoc;
}

/** create → join → start, returns the running match id (started at NOW + 2 min). */
async function runningMatch(deps: VersusDeps, puzzleId = 'he-l2-p01-03'): Promise<{ matchId: string; inviteCode: string; startedAt: number }> {
  const created = await createMatch(deps, 'host', { lang: 'he', level: 2, puzzleId }, NOW);
  await joinMatch(deps, 'guest', { inviteCode: created.inviteCode }, NOW + MIN);
  const started = await startMatch(deps, 'host', { matchId: created.matchId }, NOW + 2 * MIN);
  return { matchId: created.matchId, inviteCode: created.inviteCode, startedAt: started.startedAt as number };
}

describe('versus: invite flow', () => {
  test('create → join → start → both finish: winner and loser get trophies, rewards and leaderboard entries', async () => {
    const { db, deps } = seeded();
    const created = await createMatch(deps, 'host', { lang: 'he', level: 2, puzzleId: 'he-l2-p01-03' }, NOW);
    expect(created.inviteCode).toMatch(/^[A-Z0-9]{6}$/);
    expect(created.match).toMatchObject({ status: 'waiting', mode: 'invite', hostUid: 'host', letterCells: 64, solutionHash: HASH, expiresAt: NOW + MATCH_TIMEOUTS.waitingMs });
    expect(db.get(inviteCodePath(created.inviteCode))).toMatchObject({ kind: 'match', refId: created.matchId });
    expect(validate('match', match(db, created.matchId))).toEqual({ ok: true, errors: [] });

    const joined = await joinMatch(deps, 'guest', { inviteCode: created.inviteCode.toLowerCase() }, NOW + MIN);
    expect(joined.matchId).toBe(created.matchId);
    expect(joined.match.status).toBe('ready');
    expect(Object.keys(joined.match.players).sort()).toEqual(['guest', 'host']);
    expect(joined.match.players['guest']).toMatchObject({ displayName: 'Ben', progress: 0 });
    // a third player cannot join; a stranger cannot start
    await expect(joinMatch(deps, 'third', { inviteCode: created.inviteCode }, NOW + MIN)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(startMatch(deps, 'third', { matchId: created.matchId }, NOW + MIN)).rejects.toMatchObject({ code: 'permission-denied' });

    // guest readiness alone does not start the match; the host does
    expect((await startMatch(deps, 'guest', { matchId: created.matchId }, NOW + 90_000)).status).toBe('ready');
    const started = await startMatch(deps, 'host', { matchId: created.matchId }, NOW + 2 * MIN);
    expect(started).toEqual({ matchId: created.matchId, status: 'running', startedAt: NOW + 2 * MIN });
    expect(match(db, created.matchId).expiresAt).toBe(NOW + 2 * MIN + MATCH_TIMEOUTS.runningMs);

    // progress: shared percentages only, ≥ 1 s apart
    await reportProgress(deps, 'host', { matchId: created.matchId, progress: 0.25 }, NOW + 3 * MIN);
    await expect(reportProgress(deps, 'host', { matchId: created.matchId, progress: 0.3 }, NOW + 3 * MIN + 500)).rejects.toMatchObject({ code: 'resource-exhausted' });
    await reportProgress(deps, 'host', { matchId: created.matchId, progress: 0.5 }, NOW + 3 * MIN + 1000);
    expect(match(db, created.matchId).players['host']).toMatchObject({ progress: 0.5, lastProgressAt: NOW + 3 * MIN + 1000 });

    // host finishes first after 5 minutes
    const t1 = NOW + 7 * MIN;
    const first = await finishMatch(deps, 'host', { matchId: created.matchId, elapsedMs: 5 * MIN, hintsUsed: 1, solutionHash: HASH }, t1);
    expect(first).toMatchObject({ status: 'running', elapsedMs: 5 * MIN, result: null, opponentFinished: false });
    expect(match(db, created.matchId)).toMatchObject({ firstFinishAt: t1, expiresAt: t1 + MATCH_TIMEOUTS.finishGraceMs });

    // guest finishes 90 s later → loses
    const t2 = t1 + 90_000;
    const second = await finishMatch(deps, 'guest', { matchId: created.matchId, elapsedMs: 6 * MIN + 30_000, hintsUsed: 0, solutionHash: HASH }, t2);
    expect(second).toMatchObject({ status: 'finished', result: 'loss', opponentFinished: true, elapsedMs: 6 * MIN + 30_000 });

    const m = match(db, created.matchId);
    expect(m).toMatchObject({ status: 'finished', finishedAt: t2, closeReason: 'both_finished' });
    expect(validate('match', m)).toEqual({ ok: true, errors: [] });
    // host (120) beat guest (160): more than the +30 base; guest, the favourite, loses more than 15
    expect(m.players['host']).toMatchObject({ result: 'win', trophiesBefore: 120, trophyDelta: 32, trophiesAfter: 152 });
    expect(m.players['guest']).toMatchObject({ result: 'loss', trophiesBefore: 160, trophyDelta: -17, trophiesAfter: 143 });
    expect(m.players['host']?.rewards).toEqual({ credited: true, capped: false, coins: 40, xp: 60, seasonPoints: 25, seasonId: '2026-S1' });
    expect(m.players['guest']?.rewards).toEqual({ credited: true, capped: false, coins: 10, xp: 20, seasonPoints: 5, seasonId: '2026-S1' });

    expect(db.get('users/host')).toMatchObject({ trophies: 152, xp: 60, season: { '2026-S1': { points: 25 } }, wallet: { balance: 540 } });
    // the guest had no wallet yet: seeded with the starting wallet, then +10
    expect(db.get('users/guest')).toMatchObject({ trophies: 143, xp: 20, season: { '2026-S1': { points: 5 } }, wallet: { balance: STARTING_WALLET + 10 } });
    expect(db.get('users/guest/ledger/starting_wallet')).toMatchObject({ amount: STARTING_WALLET });
    const hostEntry = db.get(`users/host/ledger/${matchLedgerEntryId(created.matchId, 'host')}`);
    expect(hostEntry).toMatchObject({ type: 'earn_match', amount: 40, balanceAfter: 540, refId: created.matchId, server: { status: 'accepted', appliedAmount: 40, xp: 60, seasonPoints: 25 } });
    // server ids (`match_*`, like `rc_*`) are outside the client UUID v7 pattern; everything else must fit the ledger schema
    expect(validate('ledger-entry', { ...hostEntry, id: uuid7(1) })).toEqual({ ok: true, errors: [] });
    expect(db.get(trophyBoardEntryPath('he', 'host'))).toEqual({ uid: 'host', trophies: 152, displayName: 'דנה', updatedAt: t2 });
    expect(db.get(trophyBoardEntryPath('he', 'guest'))).toMatchObject({ trophies: 143, displayName: 'Ben' });
    expect(db.get('users/host/claims/earn_match~day~2026-11-10')).toMatchObject({ count: 1 });

    // idempotent re-report: nothing moves again
    const writesBefore = db.writeCount;
    const replay = await finishMatch(deps, 'guest', { matchId: created.matchId, elapsedMs: 6 * MIN + 30_000, hintsUsed: 0, solutionHash: HASH }, t2 + MIN);
    expect(replay).toMatchObject({ status: 'finished', result: 'loss', elapsedMs: 6 * MIN + 30_000 });
    expect(db.writeCount).toBe(writesBefore);
    expect(db.get('users/host')).toMatchObject({ trophies: 152, wallet: { balance: 540 } });
    await expect(reportProgress(deps, 'host', { matchId: created.matchId, progress: 0.9 }, t2 + MIN)).rejects.toMatchObject({ code: 'failed-precondition' });

    // leaderboard: guest (143) is ranked second behind host (152)
    const board = await trophyLeaderboard(db, 'guest', { lang: 'he' });
    expect(board.entries.map((e) => [e.uid, e.trophies, e.rank])).toEqual([
      ['host', 152, 1],
      ['guest', 143, 2],
    ]);
    expect(board.me).toMatchObject({ uid: 'guest', trophies: 143, rank: 2 });
    expect((await trophyLeaderboard(db, 'nobody', { lang: 'he', limit: 1 })).entries).toHaveLength(1);
    expect((await trophyLeaderboard(db, 'nobody', { lang: 'he' })).me).toBeNull();
    await expect(trophyLeaderboard(db, 'guest', { lang: 'he', limit: 101 })).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('rewards stop at the per-day cap while trophies keep moving', async () => {
    const { db, deps } = seeded({ 'users/host/claims/earn_match~day~2026-11-10': { count: MATCH_REWARDS_PER_DAY } });
    const { matchId, startedAt } = await runningMatch(deps);
    await finishMatch(deps, 'host', { matchId, elapsedMs: 4 * MIN, hintsUsed: 0, solutionHash: HASH }, startedAt + 4 * MIN);
    await finishMatch(deps, 'guest', { matchId, elapsedMs: 5 * MIN, hintsUsed: 0, solutionHash: HASH }, startedAt + 5 * MIN);
    const m = match(db, matchId);
    expect(m.players['host']).toMatchObject({ result: 'win', trophiesAfter: 152, rewards: { credited: false, capped: true, coins: 0 } });
    expect(db.get('users/host')).toMatchObject({ trophies: 152, wallet: { balance: 500 } });
    expect(db.get(`users/host/ledger/${matchLedgerEntryId(matchId, 'host')}`)).toMatchObject({ server: { status: 'rejected', appliedAmount: 0 } });
    expect(db.get('users/guest')).toMatchObject({ trophies: 143, xp: MATCH_REWARDS.lossXp });
  });

  test('cancel and leave before the start release the invite code; a server-picked puzzle comes from the pool', async () => {
    const { db, deps } = seeded();
    const created = await createMatch(deps, 'host', { lang: 'he', level: 2 }, NOW);
    expect(created.match.puzzleId).toBe('he-l2-p01-03');
    await expect(cancelMatch(deps, 'guest', { matchId: created.matchId }, NOW)).rejects.toMatchObject({ code: 'permission-denied' });
    expect(await cancelMatch(deps, 'host', { matchId: created.matchId }, NOW + MIN)).toEqual({ matchId: created.matchId, status: 'cancelled', result: null });
    expect(db.get(inviteCodePath(created.inviteCode))).toBeUndefined();
    await expect(joinMatch(deps, 'guest', { inviteCode: created.inviteCode }, NOW + MIN)).rejects.toMatchObject({ code: 'not-found' });

    // level without a pool falls back to a daily of the language
    const fallback = await createMatch(deps, 'host', { lang: 'he', level: 5 }, NOW);
    expect(fallback.match).toMatchObject({ puzzleId: 'he-d-2026-11-09-easy', letterCells: 40, solutionHash: OTHER_HASH });
    const second = await createMatch(deps, 'host', { lang: 'he', level: 2 }, NOW);
    expect((await joinMatch(deps, 'host', { inviteCode: second.inviteCode }, NOW)).match.status).toBe('waiting'); // host re-join is a no-op
    await joinMatch(deps, 'guest', { inviteCode: second.inviteCode }, NOW);
    expect((await leaveMatch(deps, 'guest', { matchId: second.matchId }, NOW)).status).toBe('cancelled');
    await expect(startMatch(deps, 'host', { matchId: second.matchId }, NOW)).rejects.toMatchObject({ code: 'failed-precondition' });
    // a running match cannot be cancelled by the host, only left
    const live = await runningMatch(deps);
    await expect(cancelMatch(deps, 'host', { matchId: live.matchId }, NOW + 3 * MIN)).rejects.toMatchObject({ code: 'failed-precondition' });
    expect((await startMatch(deps, 'guest', { matchId: live.matchId }, NOW + 3 * MIN)).status).toBe('running'); // idempotent
    await expect(finishMatch(deps, 'host', { matchId: 'missing' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(startMatch(deps, 'host', { matchId: 'missing' }, NOW)).rejects.toMatchObject({ code: 'not-found' });
    await expect(createMatch(deps, 'host', { lang: 'en', level: 3 }, NOW)).rejects.toMatchObject({ code: 'not-found' });
    await expect(createMatch(deps, 'host', { lang: 'he', level: 2, puzzleId: 'unknown-puzzle' }, NOW)).rejects.toMatchObject({ code: 'not-found' });
    await expect(createMatch(deps, 'host', { lang: 'fr', level: 2 }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(joinMatch(deps, 'guest', { inviteCode: 'AB' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
  });
});

describe('versus: cheat rejection', () => {
  test('too-fast elapsed and solution hash mismatch are refused', async () => {
    const { db, deps } = seeded();
    const { matchId, startedAt } = await runningMatch(deps);
    const serverElapsed = 10 * MIN;
    const now = startedAt + serverElapsed;
    const floor = ELAPSED_TOLERANCE * serverElapsed - 5000;
    await expect(finishMatch(deps, 'host', { matchId, elapsedMs: floor - 1, hintsUsed: 0, solutionHash: HASH }, now)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(finishMatch(deps, 'host', { matchId, elapsedMs: serverElapsed, hintsUsed: 0, solutionHash: OTHER_HASH }, now)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(finishMatch(deps, 'host', { matchId, elapsedMs: serverElapsed, hintsUsed: 0 }, now)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(finishMatch(deps, 'host', { matchId, elapsedMs: -1, hintsUsed: 0, solutionHash: HASH }, now)).rejects.toMatchObject({ code: 'invalid-argument' });
    expect(match(db, matchId).players['host']?.finishedAt).toBeUndefined();
    // the floor itself passes; the server-measured time is stored, not the client's
    const ok = await finishMatch(deps, 'host', { matchId, elapsedMs: Math.ceil(floor), hintsUsed: 0, solutionHash: HASH }, now);
    expect(ok.elapsedMs).toBe(serverElapsed);
  });

  test('a match on a puzzle without a known hash accepts any finish; finishing before the start is refused', async () => {
    const { deps } = seeded({ [matchPoolPath('he', 3)]: { puzzles: [{ puzzleId: 'he-l3-p02-01', letterCells: 70 }] } });
    const created = await createMatch(deps, 'host', { lang: 'he', level: 3 }, NOW);
    expect(created.match.solutionHash).toBeNull();
    await joinMatch(deps, 'guest', { inviteCode: created.inviteCode }, NOW);
    await expect(finishMatch(deps, 'host', { matchId: created.matchId, elapsedMs: MIN, hintsUsed: 0 }, NOW + MIN)).rejects.toMatchObject({ code: 'failed-precondition' });
    await startMatch(deps, 'host', { matchId: created.matchId }, NOW + MIN);
    await expect(finishMatch(deps, 'host', { matchId: created.matchId, elapsedMs: MIN, hintsUsed: 0 }, NOW + 2 * MIN)).resolves.toMatchObject({ elapsedMs: MIN });
  });
});

describe('versus: random matchmaking', () => {
  test('first caller is queued, second is matched into a ready match; queue entries point at it', async () => {
    const { db, deps } = seeded();
    const first = await findMatch(deps, 'host', { lang: 'he', level: 2 }, NOW);
    expect(first).toEqual({ queued: true, lang: 'he', level: 2 });
    expect(db.get(`${queueEntriesPath('he', 2)}/host`)).toMatchObject({ uid: 'host', status: 'waiting', enqueuedAt: NOW, displayName: 'דנה' });
    // calling again just refreshes the entry
    expect(await findMatch(deps, 'host', { lang: 'he', level: 2 }, NOW + 1000)).toEqual({ queued: true, lang: 'he', level: 2 });
    // a different level does not match
    expect((await findMatch(deps, 'guest', { lang: 'he', level: 1 }, NOW + 1000)).queued).toBe(true);

    const second = await findMatch(deps, 'guest', { lang: 'he', level: 2 }, NOW + 30_000);
    if (second.queued) throw new Error('expected a match');
    expect(second.match).toMatchObject({ status: 'ready', mode: 'random', inviteCode: null, hostUid: 'host', puzzleId: 'he-l2-p01-03', expiresAt: NOW + 30_000 + MATCH_TIMEOUTS.readyMs });
    expect(Object.keys(second.match.players).sort()).toEqual(['guest', 'host']);
    expect(validate('match', match(db, second.matchId))).toEqual({ ok: true, errors: [] });
    expect(db.get(`${queueEntriesPath('he', 2)}/host`)).toMatchObject({ status: 'matched', matchId: second.matchId });
    expect(db.get(`${queueEntriesPath('he', 2)}/guest`)).toMatchObject({ status: 'matched', matchId: second.matchId });

    // the queued player polling again gets the same match back instead of re-queueing
    const again = await findMatch(deps, 'host', { lang: 'he', level: 2 }, NOW + 40_000);
    expect(again).toMatchObject({ queued: false, matchId: second.matchId });
    // a guest's readiness plus the host's starts it (auto-start when both are ready)
    expect((await startMatch(deps, 'guest', { matchId: second.matchId }, NOW + 50_000)).status).toBe('ready');
    expect((await startMatch(deps, 'host', { matchId: second.matchId }, NOW + 51_000)).status).toBe('running');
  });

  test('stale queue entries (older than 2 minutes) are not matched; a third player does not pop a consumed entry', async () => {
    const { deps } = seeded({ 'users/third': { profile: { displayName: 'Cy' } } });
    await findMatch(deps, 'host', { lang: 'he', level: 2 }, NOW);
    const late = await findMatch(deps, 'guest', { lang: 'he', level: 2 }, NOW + MATCH_TIMEOUTS.queueFreshMs + 1);
    expect(late.queued).toBe(true);
    const matched = await findMatch(deps, 'third', { lang: 'he', level: 2 }, NOW + MATCH_TIMEOUTS.queueFreshMs + 2000);
    expect(matched).toMatchObject({ queued: false });
    if (matched.queued) throw new Error('expected a match');
    expect(Object.keys(matched.match.players).sort()).toEqual(['guest', 'third']);
    // host's stale entry is still waiting; a new caller only sees fresh entries
    expect((await findMatch(deps, 'guest2', { lang: 'he', level: 2 }, NOW + MATCH_TIMEOUTS.queueFreshMs + 3000)).queued).toBe(true);
  });
});

describe('versus: forfeits and expiry', () => {
  test('leaving a running match forfeits it: the opponent wins trophies, rewards only go to finishers', async () => {
    const { db, deps } = seeded();
    const { matchId, startedAt } = await runningMatch(deps);
    const left = await leaveMatch(deps, 'guest', { matchId }, startedAt + MIN);
    expect(left).toEqual({ matchId, status: 'finished', result: 'forfeit' });
    const m = match(db, matchId);
    expect(m.closeReason).toBe('forfeit');
    expect(m.players['guest']).toMatchObject({ result: 'forfeit', trophiesBefore: 160, trophiesAfter: 143, rewards: { credited: false, coins: 0 } });
    expect(m.players['host']).toMatchObject({ result: 'win', trophiesAfter: 152, rewards: { credited: false, coins: 0 } }); // did not finish → no coins
    expect(db.get('users/host')).toMatchObject({ trophies: 152, wallet: { balance: 500 } });
    expect(db.get(`users/host/ledger/${matchLedgerEntryId(matchId, 'host')}`)).toBeUndefined();
    // leaving again is a no-op
    expect(await leaveMatch(deps, 'host', { matchId }, startedAt + 2 * MIN)).toEqual({ matchId, status: 'finished', result: 'win' });
  });

  test('expireMatches: 15 minutes after the first finish the other player forfeits; the finisher keeps the win and its rewards', async () => {
    const { db, deps } = seeded();
    const { matchId, startedAt } = await runningMatch(deps);
    const t1 = startedAt + 5 * MIN;
    await finishMatch(deps, 'host', { matchId, elapsedMs: 5 * MIN, hintsUsed: 0, solutionHash: HASH }, t1);
    // too early: nothing happens
    expect(await expireMatches(deps, t1 + MATCH_TIMEOUTS.finishGraceMs - 1)).toMatchObject({ scanned: 1, forfeited: 0 });
    expect(match(db, matchId).status).toBe('running');
    const result = await expireMatches(deps, t1 + MATCH_TIMEOUTS.finishGraceMs);
    expect(result).toMatchObject({ scanned: 1, forfeited: 1, cancelled: 0, drawn: 0 });
    const m = match(db, matchId);
    expect(m).toMatchObject({ status: 'finished', closeReason: 'expired' });
    expect(m.players['host']).toMatchObject({ result: 'win', trophiesAfter: 152, rewards: { credited: true, coins: 40, xp: 60, seasonPoints: 25 } });
    expect(m.players['guest']).toMatchObject({ result: 'forfeit', trophiesAfter: 143, rewards: { credited: false, coins: 0 } });
    expect(db.get('users/host')).toMatchObject({ trophies: 152, xp: 60, wallet: { balance: 540 } });
    expect(db.get('users/guest')).toMatchObject({ trophies: 143 });
    expect(db.get('users/guest')?.['xp']).toBeUndefined();
    expect(validate('match', m)).toEqual({ ok: true, errors: [] });
    // running it again changes nothing
    expect(await expireMatches(deps, t1 + MATCH_TIMEOUTS.finishGraceMs + MIN)).toMatchObject({ scanned: 0 });
  });

  test('expireMatches: abandoned lobbies are cancelled, a running match nobody finishes is a draw, stale queue entries are deleted', async () => {
    const { db, deps } = seeded({ 'users/p3': {}, 'users/p4': {} });
    const lobby = await createMatch(deps, 'host', { lang: 'he', level: 2 }, NOW);
    const { matchId } = await runningMatch(deps);
    await findMatch(deps, 'p3', { lang: 'he', level: 1 }, NOW);
    const later = NOW + MATCH_TIMEOUTS.runningMs + 3 * MIN;
    const result = await expireMatches(deps, later);
    expect(result).toEqual({ scanned: 2, cancelled: 1, forfeited: 0, drawn: 1, queueEntriesDeleted: 1 });
    expect(match(db, lobby.matchId)).toMatchObject({ status: 'cancelled', closeReason: 'expired' });
    expect(db.get(inviteCodePath(lobby.inviteCode))).toBeUndefined();
    const drawn = match(db, matchId);
    expect(drawn.players['host']).toMatchObject({ result: 'draw', trophyDelta: 0, trophiesAfter: 120, rewards: { credited: false } });
    expect(drawn.players['guest']).toMatchObject({ result: 'draw', trophyDelta: 0, trophiesAfter: 160 });
    expect(db.get('users/host')).toMatchObject({ trophies: 120, wallet: { balance: 500 } });
    expect(db.list(queueEntriesPath('he', 1))).toEqual([]);
  });

  test('a player whose trophies would go negative stays at zero', async () => {
    const { db, deps } = seeded({ 'users/guest': { trophies: 3 } });
    const { matchId, startedAt } = await runningMatch(deps);
    await leaveMatch(deps, 'guest', { matchId }, startedAt + MIN);
    expect(db.get('users/guest')).toMatchObject({ trophies: 0 });
    expect(match(db, matchId).players['guest']).toMatchObject({ trophiesBefore: 3, trophiesAfter: 0, trophyDelta: -3 });
  });
});
