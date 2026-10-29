/**
 * `trophyLeaderboard` callable: the top entries of `trophyBoard/{lang}/entries`
 * (ordered by trophies, descending) plus the caller's own entry and rank. The
 * rank is exact: a count aggregation of entries with more trophies (one
 * aggregation read per call), so no scheduled ranking job is needed.
 */
import type { Db } from '../lib/firestore';
import { readNumber, readString } from '../lib/firestore';
import { asObject, type Lang, optionalInt, requireLang } from '../lib/input';
import { trophyBoardEntryPath } from './versus';

export const LEADERBOARD_MAX = 100;
export const LEADERBOARD_DEFAULT = 50;

export interface TrophyEntry {
  uid: string;
  displayName: string;
  trophies: number;
  updatedAt: number;
  rank: number;
}

export interface TrophyLeaderboardResult {
  lang: Lang;
  entries: TrophyEntry[];
  /** Null until the caller has played a match in this language. */
  me: TrophyEntry | null;
}

export function trophyBoardEntriesPath(lang: string): string {
  return `trophyBoard/${lang}/entries`;
}

export async function trophyLeaderboard(db: Db, uid: string, input: unknown): Promise<TrophyLeaderboardResult> {
  const o = asObject(input);
  const lang = requireLang(o);
  const limit = optionalInt(o, 'limit', 1, LEADERBOARD_MAX) ?? LEADERBOARD_DEFAULT;
  const entriesPath = trophyBoardEntriesPath(lang);
  const [rows, mine] = await Promise.all([db.queryDocs(entriesPath, [], { limit, orderBy: { field: 'trophies', direction: 'desc' } }), db.getDoc(trophyBoardEntryPath(lang, uid))]);
  const entries: TrophyEntry[] = rows.map((r, i) => ({
    uid: r.id,
    displayName: readString(r.data, 'displayName') ?? 'Player',
    trophies: readNumber(r.data, 'trophies', 0),
    updatedAt: readNumber(r.data, 'updatedAt', 0),
    rank: i + 1,
  }));
  let me: TrophyEntry | null = null;
  if (mine.exists) {
    const trophies = readNumber(mine.data, 'trophies', 0);
    const better = await db.countDocs(entriesPath, [{ field: 'trophies', op: '>', value: trophies }]);
    me = { uid, displayName: readString(mine.data, 'displayName') ?? 'Player', trophies, updatedAt: readNumber(mine.data, 'updatedAt', 0), rank: better + 1 };
  }
  return { lang, entries, me };
}
