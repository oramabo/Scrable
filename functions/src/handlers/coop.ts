/**
 * Co-op rooms (README "Multiplayer › Co-op"): up to four players fill one grid
 * together. The room document `coopRooms/{roomId}` is managed here; the grid
 * cells `coopRooms/{roomId}/cells/{cellIndex}` and the members' cursors are
 * written directly by the clients under the Firestore rules. Completion is
 * confirmed by the host and rewards every member once.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { COOP_REWARD_MIN_DURATION_MS, COOP_REWARD_MIN_MEMBERS, COOP_REWARDS, COOP_REWARDS_PER_DAY } from '../economy';
import { type Db, type DocData, type DocSnapshot, readNumber, readString, type Transaction } from '../lib/firestore';
import { inviteCodePath, newId, newInviteCode, normalizeInviteCode, type RandomSource, secureRandom } from '../lib/ids';
import { asObject, bad, type Lang, optionalString, PUZZLE_ID, requireLang, requireString, SHA256_HEX } from '../lib/input';
import { resolvePuzzle } from '../lib/puzzleLookup';
import { applyReward, readRewardState, type RewardGrant, type RewardOutcome } from '../lib/rewards';
import { displayNameOf } from '../lib/username';

export type RoomStatus = 'open' | 'running' | 'finished';

export interface RoomMember {
  displayName: string;
  /** 0..3, unique within the room; the client colours cursors and cells with it. */
  color: number;
  joinedAt: number;
  lastSeenAt: number;
  /** Letter-cell index the member is on, or null; written by the member's client. */
  cursor?: number | null;
  rewards?: RewardOutcome;
}

export interface CoopRoomDoc {
  lang: Lang;
  puzzleId: string;
  letterCells: number | null;
  solutionHash: string | null;
  hostUid: string;
  code: string | null;
  members: Record<string, RoomMember>;
  status: RoomStatus;
  createdAt: number;
  updatedAt: number;
  /** Last change made by a function (joins, start, …); members' `lastSeenAt` also count as activity. */
  lastActivityAt: number;
  startedAt?: number;
  finishedAt?: number;
  /** 'solved' | 'abandoned' | 'expired' once finished. */
  finishReason?: string;
}

export interface CoopDeps {
  db: Db;
  random?: RandomSource;
}

export const MAX_ROOM_MEMBERS = 4;
export const ROOM_IDLE_MS = 2 * 3_600_000;
export const ROOM_CODE_MS = 24 * 3_600_000;
const CODE_ATTEMPTS = 6;
const PAGE = 200;

export function roomPath(roomId: string): string {
  return `coopRooms/${roomId}`;
}
export function coopLedgerEntryId(roomId: string, uid: string): string {
  return `coop_${roomId}_${uid}`;
}

function random(deps: CoopDeps): RandomSource {
  return deps.random ?? secureRandom;
}

function readRoom(snap: DocSnapshot, roomId: string): CoopRoomDoc {
  if (!snap.exists) throw new HttpsError('not-found', `room ${roomId} does not exist`);
  return snap.data as unknown as CoopRoomDoc;
}

function memberOf(room: CoopRoomDoc, uid: string, roomId: string): RoomMember {
  const member = room.members[uid];
  if (!member) throw new HttpsError('permission-denied', `you are not a member of room ${roomId}`);
  return member;
}

function parseRoomId(o: Record<string, unknown>): string {
  return requireString(o, 'roomId', /^[A-Za-z0-9_-]{1,64}$/);
}

function compact<T extends object>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function writeRoom(tx: Transaction, roomId: string, room: CoopRoomDoc): void {
  tx.set(roomPath(roomId), compact(room) as unknown as DocData);
}

function releaseCode(tx: Transaction, room: CoopRoomDoc): void {
  if (room.code) tx.delete(inviteCodePath(room.code));
}

function freeColor(room: CoopRoomDoc): number {
  const used = new Set(Object.values(room.members).map((m) => m.color));
  for (let c = 0; c < MAX_ROOM_MEMBERS; c++) if (!used.has(c)) return c;
  return MAX_ROOM_MEMBERS - 1;
}

/** Latest activity: function-side changes or any member's heartbeat. */
export function roomLastActivity(room: CoopRoomDoc): number {
  let last = Math.max(room.lastActivityAt ?? 0, room.createdAt ?? 0, room.startedAt ?? 0);
  for (const m of Object.values(room.members ?? {})) last = Math.max(last, typeof m.lastSeenAt === 'number' ? m.lastSeenAt : 0);
  return last;
}

class CodeTaken extends Error {}

function codeIsFree(codeDoc: DocSnapshot, now: number): boolean {
  return !codeDoc.exists || readNumber(codeDoc.data, 'expiresAt', 0) <= now;
}

// ---------------------------------------------------------------------------

export interface RoomRef {
  roomId: string;
  room: CoopRoomDoc;
}

export interface CreateRoomResult extends RoomRef {
  code: string;
}

export async function createCoopRoom(deps: CoopDeps, uid: string, input: unknown, now: number): Promise<CreateRoomResult> {
  const o = asObject(input);
  const lang = requireLang(o);
  const puzzleId = requireString(o, 'puzzleId', PUZZLE_ID);
  const ref = await resolvePuzzle(deps.db, lang, puzzleId);
  const rng = random(deps);
  for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
    const code = newInviteCode(rng);
    const roomId = newId(rng);
    try {
      return await deps.db.runTransaction(async (tx) => {
        const [codeDoc, user] = await Promise.all([tx.get(inviteCodePath(code)), tx.get(`users/${uid}`)]);
        if (!codeIsFree(codeDoc, now)) throw new CodeTaken();
        const room: CoopRoomDoc = {
          lang,
          puzzleId,
          letterCells: ref?.letterCells ?? null,
          solutionHash: ref?.solutionHash ?? null,
          hostUid: uid,
          code,
          members: { [uid]: { displayName: displayNameOf(user), color: 0, joinedAt: now, lastSeenAt: now, cursor: null } },
          status: 'open',
          createdAt: now,
          updatedAt: now,
          lastActivityAt: now,
        };
        writeRoom(tx, roomId, room);
        tx.set(inviteCodePath(code), { kind: 'coop', refId: roomId, createdBy: uid, createdAt: now, expiresAt: now + ROOM_CODE_MS });
        return { roomId, code, room };
      });
    } catch (err) {
      if (!(err instanceof CodeTaken)) throw err;
    }
  }
  throw new HttpsError('resource-exhausted', 'could not allocate a room code; try again');
}

export async function joinCoopRoom(deps: CoopDeps, uid: string, input: unknown, now: number): Promise<RoomRef> {
  const o = asObject(input);
  const code = normalizeInviteCode(o['code']);
  if (code === undefined) bad('code must be six letters or digits');
  return deps.db.runTransaction(async (tx) => {
    const codeDoc = await tx.get(inviteCodePath(code));
    const roomId = readString(codeDoc.data, 'refId');
    if (codeIsFree(codeDoc, now) || readString(codeDoc.data, 'kind') !== 'coop' || roomId === undefined) {
      throw new HttpsError('not-found', 'this room code is not valid any more');
    }
    const [snap, user] = await Promise.all([tx.get(roomPath(roomId)), tx.get(`users/${uid}`)]);
    const room = readRoom(snap, roomId);
    if (room.members[uid]) return { roomId, room };
    if (room.status === 'finished') throw new HttpsError('failed-precondition', 'room is finished');
    if (Object.keys(room.members).length >= MAX_ROOM_MEMBERS) throw new HttpsError('failed-precondition', `room is full (${MAX_ROOM_MEMBERS} players)`);
    room.members[uid] = { displayName: displayNameOf(user), color: freeColor(room), joinedAt: now, lastSeenAt: now, cursor: null };
    room.updatedAt = now;
    room.lastActivityAt = now;
    writeRoom(tx, roomId, room);
    return { roomId, room };
  });
}

/** The host marks the room as running (members may still join while there is space). */
export async function startCoopRoom(deps: CoopDeps, uid: string, input: unknown, now: number): Promise<RoomRef> {
  const roomId = parseRoomId(asObject(input));
  return deps.db.runTransaction(async (tx) => {
    const room = readRoom(await tx.get(roomPath(roomId)), roomId);
    memberOf(room, uid, roomId);
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', 'only the host can start the room');
    if (room.status === 'running') return { roomId, room };
    if (room.status !== 'open') throw new HttpsError('failed-precondition', `room is ${room.status}`);
    room.status = 'running';
    room.startedAt = now;
    room.updatedAt = now;
    room.lastActivityAt = now;
    writeRoom(tx, roomId, room);
    return { roomId, room };
  });
}

export interface LeaveRoomResult {
  roomId: string;
  status: RoomStatus;
  hostUid: string;
}

/** Removes the caller; the earliest remaining member inherits the host role; an empty room is closed. */
export async function leaveCoopRoom(deps: CoopDeps, uid: string, input: unknown, now: number): Promise<LeaveRoomResult> {
  const roomId = parseRoomId(asObject(input));
  return deps.db.runTransaction(async (tx) => {
    const room = readRoom(await tx.get(roomPath(roomId)), roomId);
    if (!room.members[uid] || room.status === 'finished') return { roomId, status: room.status, hostUid: room.hostUid };
    delete room.members[uid];
    room.updatedAt = now;
    room.lastActivityAt = now;
    const remaining = Object.entries(room.members).sort((a, b) => a[1].joinedAt - b[1].joinedAt || (a[0] < b[0] ? -1 : 1));
    if (remaining.length === 0) {
      room.status = 'finished';
      room.finishedAt = now;
      room.finishReason = 'abandoned';
      releaseCode(tx, room);
    } else if (room.hostUid === uid) {
      room.hostUid = (remaining[0] as [string, RoomMember])[0];
    }
    writeRoom(tx, roomId, room);
    return { roomId, status: room.status, hostUid: room.hostUid };
  });
}

export interface FinishRoomResult {
  roomId: string;
  status: RoomStatus;
  rewarded: boolean;
  members: Record<string, RewardOutcome>;
}

function grantFor(roomId: string, uid: string): RewardGrant {
  return {
    entryId: coopLedgerEntryId(roomId, uid),
    type: 'earn_coop',
    coins: COOP_REWARDS.coins,
    xp: COOP_REWARDS.xp,
    seasonPoints: 0,
    refId: roomId,
    perDay: COOP_REWARDS_PER_DAY,
  };
}

/** Whether a completion pays: at least two members and a room older than a minute (anti-farming). */
export function roomRewardable(room: CoopRoomDoc, now: number): boolean {
  return Object.keys(room.members).length >= COOP_REWARD_MIN_MEMBERS && now - room.createdAt >= COOP_REWARD_MIN_DURATION_MS;
}

/** The host confirms the grid is complete; every current member is rewarded once (`coop_{roomId}_{uid}`). */
export async function finishCoopRoom(deps: CoopDeps, uid: string, input: unknown, now: number): Promise<FinishRoomResult> {
  const o = asObject(input);
  const roomId = parseRoomId(o);
  const solutionHash = optionalString(o, 'solutionHash', SHA256_HEX, 'lowercase hex sha256');
  return deps.db.runTransaction(async (tx) => {
    const room = readRoom(await tx.get(roomPath(roomId)), roomId);
    memberOf(room, uid, roomId);
    const summary = (): Record<string, RewardOutcome> => {
      const out: Record<string, RewardOutcome> = {};
      for (const [m, member] of Object.entries(room.members)) if (member.rewards) out[m] = member.rewards;
      return out;
    };
    if (room.status === 'finished') return { roomId, status: room.status, rewarded: room.finishReason === 'solved', members: summary() };
    if (room.hostUid !== uid) throw new HttpsError('permission-denied', 'only the host can confirm completion');
    if (room.solutionHash !== null) {
      if (solutionHash === undefined) bad('solutionHash is required for this room');
      if (solutionHash !== room.solutionHash) throw new HttpsError('failed-precondition', 'solution hash mismatch');
    }
    const rewarded = roomRewardable(room, now);
    const uids = Object.keys(room.members);
    const reads = rewarded ? await Promise.all(uids.map((m) => readRewardState(tx, m, grantFor(roomId, m), now))) : [];
    if (rewarded) {
      uids.forEach((m, i) => {
        const { outcome, userPatch } = applyReward(tx, m, reads[i] as Awaited<ReturnType<typeof readRewardState>>, grantFor(roomId, m), now);
        (room.members[m] as RoomMember).rewards = outcome;
        tx.set(`users/${m}`, { ...userPatch, lastCoopAt: now }, { merge: true });
      });
    }
    room.status = 'finished';
    room.finishedAt = now;
    room.finishReason = 'solved';
    room.updatedAt = now;
    room.lastActivityAt = now;
    writeRoom(tx, roomId, room);
    releaseCode(tx, room);
    return { roomId, status: room.status, rewarded, members: summary() };
  });
}

export interface ExpireRoomsResult {
  scanned: number;
  expired: number;
}

/** Closes rooms with no activity (function writes or member heartbeats) for ROOM_IDLE_MS. */
export async function expireRooms(deps: CoopDeps, now: number): Promise<ExpireRoomsResult> {
  const result: ExpireRoomsResult = { scanned: 0, expired: 0 };
  let startAfterId: string | undefined;
  for (;;) {
    const page = await deps.db.queryDocs('coopRooms', [{ field: 'status', op: 'in', value: ['open', 'running'] }], { limit: PAGE, startAfterId });
    for (const snap of page) {
      result.scanned++;
      if (roomLastActivity(snap.data as unknown as CoopRoomDoc) > now - ROOM_IDLE_MS) continue;
      const expired = await deps.db.runTransaction(async (tx) => {
        const fresh = await tx.get(snap.path);
        if (!fresh.exists) return false;
        const room = fresh.data as unknown as CoopRoomDoc;
        if (room.status === 'finished' || roomLastActivity(room) > now - ROOM_IDLE_MS) return false;
        room.status = 'finished';
        room.finishedAt = now;
        room.finishReason = 'expired';
        room.updatedAt = now;
        writeRoom(tx, snap.id, room);
        releaseCode(tx, room);
        return true;
      });
      if (expired) result.expired++;
    }
    if (page.length < PAGE) break;
    startAfterId = page[page.length - 1]?.id;
  }
  return result;
}
