/**
 * Versus races (README "Multiplayer › Versus"): two players solve the same
 * puzzle; only progress percentages are shared. Match documents live in
 * `matches/{matchId}`, invite codes in `inviteCodes/{code}`, matchmaking
 * entries in `matchQueue/{lang}_{level}/entries/{uid}`. Results move trophies
 * (src/lib/trophies.ts), the trophy leaderboard and the rewards
 * (src/lib/rewards.ts) in one transaction when the match finishes.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { MATCH_REWARDS, MATCH_REWARDS_PER_DAY } from '../economy';
import { type Db, type DocData, type DocSnapshot, readNumber, readString, type Transaction } from '../lib/firestore';
import { inviteCodePath, newId, newInviteCode, normalizeInviteCode, type RandomSource, secureRandom } from '../lib/ids';
import { asObject, bad, type Lang, optionalString, PUZZLE_ID, requireInt, requireLang, requireNumber, requireString, SHA256_HEX } from '../lib/input';
import { pickRandomPuzzle, type PuzzleRef, resolvePuzzle } from '../lib/puzzleLookup';
import { applyReward, readRewardState, type RewardGrant, type RewardOutcome, type RewardReads } from '../lib/rewards';
import { applyTrophyDelta, type MatchResult, trophyDelta } from '../lib/trophies';
import { displayNameOf } from '../lib/username';

export type MatchStatus = 'waiting' | 'ready' | 'running' | 'finished' | 'cancelled';
export type MatchMode = 'invite' | 'random';

export interface MatchPlayer {
  displayName: string;
  joinedAt: number;
  /** 0..1, reported by the player's client. */
  progress: number;
  lastProgressAt?: number;
  ready?: boolean;
  finishedAt?: number;
  /** Server-measured solve time (startedAt → finish). */
  elapsedMs?: number;
  hintsUsed?: number;
  result?: MatchResult;
  trophiesBefore?: number;
  trophiesAfter?: number;
  trophyDelta?: number;
  rewards?: { coins: number; xp: number; seasonPoints: number; seasonId: string | null; credited: boolean; capped: boolean };
}

export interface MatchDoc {
  lang: Lang;
  level: number;
  puzzleId: string;
  letterCells: number | null;
  solutionHash: string | null;
  mode: MatchMode;
  inviteCode: string | null;
  hostUid: string;
  players: Record<string, MatchPlayer>;
  status: MatchStatus;
  createdAt: number;
  updatedAt: number;
  startedAt?: number;
  firstFinishAt?: number;
  finishedAt?: number;
  /** 'both_finished' | 'forfeit' | 'expired' | 'cancelled' once the match is closed. */
  closeReason?: string;
  expiresAt: number;
}

export interface VersusDeps {
  db: Db;
  random?: RandomSource;
}

/** Lifetimes (ms): a lobby waiting for the guest, a ready match waiting for its start, a running match, the grace after the first finish. */
export const MATCH_TIMEOUTS = {
  waitingMs: 30 * 60_000,
  readyMs: 10 * 60_000,
  runningMs: 60 * 60_000,
  finishGraceMs: 15 * 60_000,
  /** A matchmaking entry is only matched within this long of being enqueued. */
  queueFreshMs: 2 * 60_000,
  /** Queue entries (matched or stale) are deleted after this long. */
  queueRetentionMs: 10 * 60_000,
  progressMinIntervalMs: 1000,
  inviteCodeMs: 30 * 60_000,
} as const;

/** The client's elapsed must be at least `tolerance × server elapsed − slack`. */
export const ELAPSED_TOLERANCE = 0.7;
export const ELAPSED_SLACK_MS = 5000;
const MAX_ELAPSED_MS = 24 * 3_600_000;
const MAX_LEVEL = 9;
const CODE_ATTEMPTS = 6;
const PLAYERS_PER_MATCH = 2;

export function matchPath(matchId: string): string {
  return `matches/${matchId}`;
}
export function queueKey(lang: string, level: number): string {
  return `${lang}_${level}`;
}
export function queueEntriesPath(lang: string, level: number): string {
  return `matchQueue/${queueKey(lang, level)}/entries`;
}
export function trophyBoardEntryPath(lang: string, uid: string): string {
  return `trophyBoard/${lang}/entries/${uid}`;
}
export function matchLedgerEntryId(matchId: string, uid: string): string {
  return `match_${matchId}_${uid}`;
}

function random(deps: VersusDeps): RandomSource {
  return deps.random ?? secureRandom;
}

function readMatch(snap: DocSnapshot, matchId: string): MatchDoc {
  if (!snap.exists) throw new HttpsError('not-found', `match ${matchId} does not exist`);
  return snap.data as unknown as MatchDoc;
}

function playerOf(match: MatchDoc, uid: string, matchId: string): MatchPlayer {
  const player = match.players[uid];
  if (!player) throw new HttpsError('permission-denied', `you are not a player of match ${matchId}`);
  return player;
}

function opponentUid(match: MatchDoc, uid: string): string | undefined {
  return Object.keys(match.players).find((u) => u !== uid);
}

function parseMatchId(o: Record<string, unknown>): string {
  return requireString(o, 'matchId', /^[A-Za-z0-9_-]{1,64}$/);
}

/** Strips undefined values (Firestore rejects them) so optional fields can be built naturally. */
function compact<T extends object>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function writeMatch(tx: Transaction, matchId: string, match: MatchDoc): void {
  tx.set(matchPath(matchId), compact(match) as unknown as DocData);
}

function newMatch(ref: PuzzleRef, lang: Lang, level: number, mode: MatchMode, hostUid: string, now: number): MatchDoc {
  return {
    lang,
    level,
    puzzleId: ref.puzzleId,
    letterCells: ref.letterCells,
    solutionHash: ref.solutionHash,
    mode,
    inviteCode: null,
    hostUid,
    players: {},
    status: 'waiting',
    createdAt: now,
    updatedAt: now,
    expiresAt: now + MATCH_TIMEOUTS.waitingMs,
  };
}

function newPlayer(user: DocSnapshot, now: number): MatchPlayer {
  return { displayName: displayNameOf(user), joinedAt: now, progress: 0 };
}

/** Thrown inside a transaction when the candidate invite code is taken; the caller retries with a new code. */
class CodeTaken extends Error {}

function codeIsFree(codeDoc: DocSnapshot, now: number): boolean {
  return !codeDoc.exists || readNumber(codeDoc.data, 'expiresAt', 0) <= now;
}

// ---------------------------------------------------------------------------
// createMatch

export interface CreateMatchResult {
  matchId: string;
  inviteCode: string;
  match: MatchDoc;
}

export async function createMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<CreateMatchResult> {
  const o = asObject(input);
  const lang = requireLang(o);
  const level = requireInt(o, 'level', 1, MAX_LEVEL);
  const puzzleId = optionalString(o, 'puzzleId', PUZZLE_ID);
  const rng = random(deps);
  const ref = puzzleId === undefined ? await pickRandomPuzzle(deps.db, lang, level, rng) : await resolvePuzzle(deps.db, lang, puzzleId, level);
  if (!ref) throw new HttpsError('not-found', puzzleId === undefined ? `no puzzle available for ${lang} level ${level}` : `unknown puzzle ${puzzleId}`);

  for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
    const code = newInviteCode(rng);
    const matchId = newId(rng);
    try {
      return await deps.db.runTransaction(async (tx) => {
        const [codeDoc, user] = await Promise.all([tx.get(inviteCodePath(code)), tx.get(`users/${uid}`)]);
        if (!codeIsFree(codeDoc, now)) throw new CodeTaken();
        const match = newMatch(ref, lang, level, 'invite', uid, now);
        match.inviteCode = code;
        match.players[uid] = newPlayer(user, now);
        writeMatch(tx, matchId, match);
        tx.set(inviteCodePath(code), { kind: 'match', refId: matchId, createdBy: uid, createdAt: now, expiresAt: now + MATCH_TIMEOUTS.inviteCodeMs });
        return { matchId, inviteCode: code, match };
      });
    } catch (err) {
      if (!(err instanceof CodeTaken)) throw err;
    }
  }
  throw new HttpsError('resource-exhausted', 'could not allocate an invite code; try again');
}

// ---------------------------------------------------------------------------
// joinMatch

export interface MatchRef {
  matchId: string;
  match: MatchDoc;
}

export async function joinMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<MatchRef> {
  const o = asObject(input);
  const code = normalizeInviteCode(o['inviteCode']);
  if (code === undefined) bad('inviteCode must be six letters or digits');
  return deps.db.runTransaction(async (tx) => {
    const codeDoc = await tx.get(inviteCodePath(code));
    const matchId = readString(codeDoc.data, 'refId');
    if (codeIsFree(codeDoc, now) || readString(codeDoc.data, 'kind') !== 'match' || matchId === undefined) {
      throw new HttpsError('not-found', 'this invite code is not valid any more');
    }
    const [snap, user] = await Promise.all([tx.get(matchPath(matchId)), tx.get(`users/${uid}`)]);
    const match = readMatch(snap, matchId);
    if (match.players[uid]) return { matchId, match };
    if (match.status !== 'waiting') throw new HttpsError('failed-precondition', `match is ${match.status}`);
    if (Object.keys(match.players).length >= PLAYERS_PER_MATCH) throw new HttpsError('failed-precondition', 'match is full');
    match.players[uid] = newPlayer(user, now);
    match.status = 'ready';
    match.updatedAt = now;
    match.expiresAt = now + MATCH_TIMEOUTS.readyMs;
    writeMatch(tx, matchId, match);
    return { matchId, match };
  });
}

// ---------------------------------------------------------------------------
// findMatch (random matchmaking)

export type FindMatchResult = { queued: true; lang: Lang; level: number } | { queued: false; matchId: string; match: MatchDoc };

interface QueueEntry {
  uid: string;
  status: 'waiting' | 'matched';
  enqueuedAt: number;
  matchId?: string;
}

function readQueueEntry(snap: DocSnapshot): QueueEntry | undefined {
  const uid = readString(snap.data, 'uid');
  const status = readString(snap.data, 'status');
  if (uid === undefined || (status !== 'waiting' && status !== 'matched')) return undefined;
  const entry: QueueEntry = { uid, status, enqueuedAt: readNumber(snap.data, 'enqueuedAt', 0) };
  const matchId = readString(snap.data, 'matchId');
  if (matchId !== undefined) entry.matchId = matchId;
  return entry;
}

function isFreshWaiting(entry: QueueEntry | undefined, now: number): entry is QueueEntry {
  return entry !== undefined && entry.status === 'waiting' && entry.enqueuedAt > now - MATCH_TIMEOUTS.queueFreshMs && entry.enqueuedAt <= now + 60_000;
}

export async function findMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<FindMatchResult> {
  const o = asObject(input);
  const lang = requireLang(o);
  const level = requireInt(o, 'level', 1, MAX_LEVEL);
  const entries = queueEntriesPath(lang, level);
  const ownPath = `${entries}/${uid}`;

  // Already matched by someone who popped our entry? Hand that match back while it is alive.
  const own = readQueueEntry(await deps.db.getDoc(ownPath));
  if (own?.status === 'matched' && own.matchId !== undefined) {
    const snap = await deps.db.getDoc(matchPath(own.matchId));
    if (snap.exists) {
      const match = snap.data as unknown as MatchDoc;
      if ((match.status === 'ready' || match.status === 'running') && match.players[uid]) return { queued: false, matchId: own.matchId, match };
    }
  }

  const candidates = (await deps.db.queryDocs(entries, [{ field: 'status', op: '==', value: 'waiting' }], { limit: 50 }))
    .map(readQueueEntry)
    .filter((e): e is QueueEntry => isFreshWaiting(e, now) && e.uid !== uid)
    .sort((a, b) => a.enqueuedAt - b.enqueuedAt || (a.uid < b.uid ? -1 : 1));

  if (candidates.length > 0) {
    const ref = await pickRandomPuzzle(deps.db, lang, level, random(deps));
    if (!ref) throw new HttpsError('not-found', `no puzzle available for ${lang} level ${level}`);
    for (const candidate of candidates) {
      const matchId = newId(random(deps));
      const candidatePath = `${entries}/${candidate.uid}`;
      const matched = await deps.db.runTransaction(async (tx): Promise<MatchDoc | undefined> => {
        const [theirs, me, them] = await Promise.all([tx.get(candidatePath), tx.get(`users/${uid}`), tx.get(`users/${candidate.uid}`)]);
        if (!isFreshWaiting(readQueueEntry(theirs), now)) return undefined; // popped by someone else meanwhile
        const match = newMatch(ref, lang, level, 'random', candidate.uid, now);
        match.players[candidate.uid] = newPlayer(them, now);
        match.players[uid] = newPlayer(me, now);
        match.status = 'ready';
        match.expiresAt = now + MATCH_TIMEOUTS.readyMs;
        writeMatch(tx, matchId, match);
        const matchedEntry = { status: 'matched', matchId, matchedAt: now, lang, level };
        tx.set(candidatePath, { uid: candidate.uid, enqueuedAt: candidate.enqueuedAt, ...matchedEntry });
        tx.set(ownPath, { uid, enqueuedAt: now, ...matchedEntry });
        return match;
      });
      if (matched) return { queued: false, matchId, match: matched };
    }
  }

  await deps.db.runTransaction(async (tx) => {
    const user = await tx.get(`users/${uid}`);
    tx.set(`matchQueue/${queueKey(lang, level)}`, { lang, level, updatedAt: now }, { merge: true });
    tx.set(ownPath, { uid, status: 'waiting', enqueuedAt: now, lang, level, displayName: displayNameOf(user) });
  });
  return { queued: true, lang, level };
}

// ---------------------------------------------------------------------------
// startMatch / reportProgress

export interface StartMatchResult {
  matchId: string;
  status: MatchStatus;
  startedAt: number | null;
}

/** The host starts a ready match; a guest marks itself ready and the match starts automatically once both have. */
export async function startMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<StartMatchResult> {
  const matchId = parseMatchId(asObject(input));
  return deps.db.runTransaction(async (tx) => {
    const match = readMatch(await tx.get(matchPath(matchId)), matchId);
    const me = playerOf(match, uid, matchId);
    if (match.status === 'running') return { matchId, status: match.status, startedAt: match.startedAt ?? null };
    if (match.status !== 'ready') throw new HttpsError('failed-precondition', `match is ${match.status}`);
    me.ready = true;
    const everyoneReady = Object.values(match.players).every((p) => p.ready === true);
    if (uid === match.hostUid || everyoneReady) {
      match.status = 'running';
      match.startedAt = now;
      match.expiresAt = now + MATCH_TIMEOUTS.runningMs;
    }
    match.updatedAt = now;
    writeMatch(tx, matchId, match);
    return { matchId, status: match.status, startedAt: match.startedAt ?? null };
  });
}

export async function reportProgress(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<{ matchId: string; progress: number }> {
  const o = asObject(input);
  const matchId = parseMatchId(o);
  const progress = requireNumber(o, 'progress', 0, 1);
  return deps.db.runTransaction(async (tx) => {
    const match = readMatch(await tx.get(matchPath(matchId)), matchId);
    const me = playerOf(match, uid, matchId);
    if (match.status !== 'running') throw new HttpsError('failed-precondition', `match is ${match.status}`);
    if (me.finishedAt !== undefined) return { matchId, progress: 1 };
    if (me.lastProgressAt !== undefined && now - me.lastProgressAt < MATCH_TIMEOUTS.progressMinIntervalMs) {
      throw new HttpsError('resource-exhausted', 'progress may be reported at most once per second');
    }
    tx.set(matchPath(matchId), { players: { [uid]: { progress, lastProgressAt: now } }, updatedAt: now }, { merge: true });
    return { matchId, progress };
  });
}

// ---------------------------------------------------------------------------
// Settlement: results → trophies, leaderboard, rewards

function grantFor(matchId: string, uid: string, result: MatchResult): RewardGrant {
  const win = result === 'win';
  return {
    entryId: matchLedgerEntryId(matchId, uid),
    type: 'earn_match',
    coins: win ? MATCH_REWARDS.winCoins : MATCH_REWARDS.lossCoins,
    xp: win ? MATCH_REWARDS.winXp : MATCH_REWARDS.lossXp,
    seasonPoints: win ? MATCH_REWARDS.winSeasonPoints : MATCH_REWARDS.lossSeasonPoints,
    refId: matchId,
    perDay: MATCH_REWARDS_PER_DAY,
  };
}

interface SettleReads {
  uid: string;
  user: DocSnapshot;
  /** Present when the player earns coins/XP/season points for this result. */
  reward?: { grant: RewardGrant; reads: RewardReads };
}

/** Rewards go to players who actually finished the puzzle and did not draw; trophies move for every win/loss/forfeit. */
function rewardable(player: MatchPlayer, result: MatchResult): boolean {
  return (result === 'win' || result === 'loss') && player.finishedAt !== undefined;
}

async function readSettleState(tx: Transaction, matchId: string, match: MatchDoc, results: Record<string, MatchResult>, now: number): Promise<SettleReads[]> {
  return Promise.all(
    Object.entries(results).map(async ([uid, result]): Promise<SettleReads> => {
      const player = match.players[uid] as MatchPlayer;
      if (!rewardable(player, result)) return { uid, user: await tx.get(`users/${uid}`) };
      const grant = grantFor(matchId, uid, result);
      const reads = await readRewardState(tx, uid, grant, now);
      return { uid, user: reads.user, reward: { grant, reads } };
    }),
  );
}

const NO_REWARD: RewardOutcome = { credited: false, capped: false, coins: 0, xp: 0, seasonPoints: 0, seasonId: null };

/** Writes the closed match, both users (trophies + rewards) and both leaderboard entries. All reads must have happened already. */
function applySettlement(tx: Transaction, matchId: string, match: MatchDoc, results: Record<string, MatchResult>, reads: SettleReads[], now: number, reason: string): void {
  const trophies = new Map<string, number>();
  for (const r of reads) trophies.set(r.uid, Math.max(0, readNumber(r.user.data, 'trophies', 0)));
  for (const r of reads) {
    const result = results[r.uid] as MatchResult;
    const player = match.players[r.uid] as MatchPlayer;
    const mine = trophies.get(r.uid) as number;
    const opponent = Object.keys(results).find((u) => u !== r.uid);
    const theirs = opponent === undefined ? mine : (trophies.get(opponent) as number);
    const delta = trophyDelta(result, mine, theirs);
    const after = applyTrophyDelta(mine, delta);
    const reward = r.reward ? applyReward(tx, r.uid, r.reward.reads, r.reward.grant, now) : { outcome: NO_REWARD, userPatch: {} as DocData };
    player.result = result;
    player.trophiesBefore = mine;
    player.trophiesAfter = after;
    player.trophyDelta = after - mine;
    player.rewards = { ...reward.outcome };
    tx.set(`users/${r.uid}`, { ...reward.userPatch, trophies: after, lastMatchAt: now }, { merge: true });
    tx.set(trophyBoardEntryPath(match.lang, r.uid), { uid: r.uid, trophies: after, displayName: player.displayName, updatedAt: now });
  }
  match.status = 'finished';
  match.finishedAt = now;
  match.closeReason = reason;
  match.updatedAt = now;
  writeMatch(tx, matchId, match);
}

/** Closes a running match inside `tx`: reads first, then every write. */
async function settle(tx: Transaction, matchId: string, match: MatchDoc, results: Record<string, MatchResult>, now: number, reason: string): Promise<void> {
  const reads = await readSettleState(tx, matchId, match, results, now);
  applySettlement(tx, matchId, match, results, reads, now, reason);
}

function cancel(tx: Transaction, matchId: string, match: MatchDoc, now: number, reason: string): void {
  match.status = 'cancelled';
  match.finishedAt = now;
  match.closeReason = reason;
  match.updatedAt = now;
  writeMatch(tx, matchId, match);
  if (match.inviteCode) tx.delete(inviteCodePath(match.inviteCode));
}

// ---------------------------------------------------------------------------
// finishMatch

export interface FinishMatchResult {
  matchId: string;
  status: MatchStatus;
  /** Server-measured solve time. */
  elapsedMs: number;
  /** Known once the match is closed. */
  result: MatchResult | null;
  opponentFinished: boolean;
  player: MatchPlayer;
}

export async function finishMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<FinishMatchResult> {
  const o = asObject(input);
  const matchId = parseMatchId(o);
  const elapsedMs = requireInt(o, 'elapsedMs', 0, MAX_ELAPSED_MS);
  const hintsUsed = requireInt(o, 'hintsUsed', 0, 10_000);
  const solutionHash = optionalString(o, 'solutionHash', SHA256_HEX, 'lowercase hex sha256');

  return deps.db.runTransaction(async (tx) => {
    const match = readMatch(await tx.get(matchPath(matchId)), matchId);
    const me = playerOf(match, uid, matchId);
    const otherUid = opponentUid(match, uid);
    const other = otherUid === undefined ? undefined : match.players[otherUid];
    const done = (): FinishMatchResult => ({
      matchId,
      status: match.status,
      elapsedMs: me.elapsedMs ?? 0,
      result: me.result ?? null,
      opponentFinished: other?.finishedAt !== undefined,
      player: me,
    });
    if (me.finishedAt !== undefined) return done(); // idempotent replay
    if (match.status !== 'running' || match.startedAt === undefined) throw new HttpsError('failed-precondition', `match is ${match.status}`);
    const serverElapsed = Math.max(0, now - match.startedAt);
    if (elapsedMs < ELAPSED_TOLERANCE * serverElapsed - ELAPSED_SLACK_MS) {
      throw new HttpsError('failed-precondition', `elapsedMs ${elapsedMs} is implausible: the match has been running for ${serverElapsed} ms`);
    }
    if (match.solutionHash !== null) {
      if (solutionHash === undefined) bad('solutionHash is required for this match');
      if (solutionHash !== match.solutionHash) throw new HttpsError('failed-precondition', 'solution hash mismatch');
    }
    me.finishedAt = now;
    me.elapsedMs = serverElapsed;
    me.hintsUsed = hintsUsed;
    me.progress = 1;
    me.lastProgressAt = now;
    match.updatedAt = now;

    if (other !== undefined && otherUid !== undefined && other.finishedAt !== undefined) {
      // Second finisher: the earlier finish wins; identical server times draw.
      const tie = (other.elapsedMs ?? 0) === serverElapsed;
      const results: Record<string, MatchResult> = tie ? { [uid]: 'draw', [otherUid]: 'draw' } : { [uid]: 'loss', [otherUid]: 'win' };
      await settle(tx, matchId, match, results, now, 'both_finished');
      return done();
    }
    match.firstFinishAt = now;
    match.expiresAt = Math.min(match.expiresAt, now + MATCH_TIMEOUTS.finishGraceMs);
    writeMatch(tx, matchId, match);
    return done();
  });
}

// ---------------------------------------------------------------------------
// leaveMatch / cancelMatch

export interface CloseMatchResult {
  matchId: string;
  status: MatchStatus;
  result: MatchResult | null;
}

/** Leaving before the start cancels the match; leaving a running match forfeits it (the opponent wins). */
export async function leaveMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<CloseMatchResult> {
  const matchId = parseMatchId(asObject(input));
  return deps.db.runTransaction(async (tx) => {
    const match = readMatch(await tx.get(matchPath(matchId)), matchId);
    const me = playerOf(match, uid, matchId);
    const done = (): CloseMatchResult => ({ matchId, status: match.status, result: me.result ?? null });
    if (match.status === 'finished' || match.status === 'cancelled') return done();
    if (match.status === 'waiting' || match.status === 'ready') {
      cancel(tx, matchId, match, now, 'cancelled');
      return done();
    }
    if (me.finishedAt !== undefined) return done(); // already finished: nothing to forfeit, the opponent still has their grace period
    const otherUid = opponentUid(match, uid);
    const results: Record<string, MatchResult> = { [uid]: 'forfeit' };
    if (otherUid !== undefined) results[otherUid] = 'win';
    match.updatedAt = now;
    await settle(tx, matchId, match, results, now, 'forfeit');
    return done();
  });
}

/** The host cancels a match that has not started. */
export async function cancelMatch(deps: VersusDeps, uid: string, input: unknown, now: number): Promise<CloseMatchResult> {
  const matchId = parseMatchId(asObject(input));
  return deps.db.runTransaction(async (tx) => {
    const match = readMatch(await tx.get(matchPath(matchId)), matchId);
    playerOf(match, uid, matchId);
    if (match.hostUid !== uid) throw new HttpsError('permission-denied', 'only the host can cancel a match');
    if (match.status === 'finished' || match.status === 'cancelled') return { matchId, status: match.status, result: null };
    if (match.status === 'running') throw new HttpsError('failed-precondition', 'a running match cannot be cancelled; use leaveMatch');
    cancel(tx, matchId, match, now, 'cancelled');
    return { matchId, status: match.status, result: null };
  });
}

// ---------------------------------------------------------------------------
// expireMatches (scheduled)

export interface ExpireMatchesResult {
  scanned: number;
  cancelled: number;
  forfeited: number;
  drawn: number;
  queueEntriesDeleted: number;
}

const PAGE = 200;

/** Closes matches past `expiresAt`: lobbies are cancelled, a running match with one finisher is a forfeit, with none a draw. Stale queue entries are deleted. */
export async function expireMatches(deps: VersusDeps, now: number): Promise<ExpireMatchesResult> {
  const result: ExpireMatchesResult = { scanned: 0, cancelled: 0, forfeited: 0, drawn: 0, queueEntriesDeleted: 0 };
  let startAfterId: string | undefined;
  for (;;) {
    const page = await deps.db.queryDocs('matches', [{ field: 'status', op: 'in', value: ['waiting', 'ready', 'running'] }], { limit: PAGE, startAfterId });
    for (const snap of page) {
      result.scanned++;
      if (readNumber(snap.data, 'expiresAt', Number.POSITIVE_INFINITY) > now) continue;
      const outcome = await deps.db.runTransaction(async (tx): Promise<'cancelled' | 'forfeited' | 'drawn' | undefined> => {
        const fresh = await tx.get(snap.path);
        if (!fresh.exists) return undefined;
        const match = fresh.data as unknown as MatchDoc;
        if (match.expiresAt > now) return undefined;
        if (match.status === 'waiting' || match.status === 'ready') {
          cancel(tx, snap.id, match, now, 'expired');
          return 'cancelled';
        }
        if (match.status !== 'running') return undefined;
        const uids = Object.keys(match.players);
        const finished = uids.filter((u) => match.players[u]?.finishedAt !== undefined);
        const results: Record<string, MatchResult> = {};
        if (finished.length === 1) {
          for (const u of uids) results[u] = finished.includes(u) ? 'win' : 'forfeit';
          await settle(tx, snap.id, match, results, now, 'expired');
          return 'forfeited';
        }
        for (const u of uids) results[u] = 'draw';
        await settle(tx, snap.id, match, results, now, 'expired');
        return 'drawn';
      });
      if (outcome) result[outcome]++;
    }
    if (page.length < PAGE) break;
    startAfterId = page[page.length - 1]?.id;
  }

  const queues = await deps.db.queryDocs('matchQueue', [], { limit: PAGE });
  for (const queue of queues) {
    const entries = await deps.db.queryDocs(`${queue.path}/entries`, [], { limit: PAGE });
    for (const entry of entries) {
      const at = Math.max(readNumber(entry.data, 'enqueuedAt', 0), readNumber(entry.data, 'matchedAt', 0));
      if (at <= now - MATCH_TIMEOUTS.queueRetentionMs) {
        await deps.db.deleteDoc(entry.path);
        result.queueEntriesDeleted++;
      }
    }
  }
  return result;
}
