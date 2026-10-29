/**
 * Resolves the puzzle a match or co-op room is played on. Sources, in order:
 *  1. `matchPool/{lang}_{level}` — `{puzzles: [{puzzleId, letterCells, solutionHash?}]}`
 *     filled by the publisher (admin tool) with pack puzzles suited to racing;
 *  2. `dailies/*` of the language (written by `publishPuzzle`);
 *  3. `puzzleIndex/{puzzleId}` (written by `publishPuzzle` for every puzzle).
 */
import { type Db, type DocData, type Filter, getField, readNumber, readString } from './firestore';
import type { RandomSource } from './ids';

export interface PuzzleRef {
  puzzleId: string;
  /** Letter cells (plausibility floor); null when the source does not know it. */
  letterCells: number | null;
  /** `PuzzleCodec.solutionHash`; null when unknown (then finish hashes are not checked). */
  solutionHash: string | null;
  source: 'pool' | 'daily' | 'index';
}

export function matchPoolPath(lang: string, level: number): string {
  return `matchPool/${lang}_${level}`;
}

export function puzzleIndexPath(puzzleId: string): string {
  return `puzzleIndex/${puzzleId}`;
}

function refFrom(data: DocData | undefined, source: PuzzleRef['source'], idField = 'puzzleId'): PuzzleRef | undefined {
  const puzzleId = readString(data, idField);
  if (puzzleId === undefined) return undefined;
  const letterCells = readNumber(data, 'letterCells', 0);
  const hash = readString(data, 'solutionHash');
  return { puzzleId, letterCells: letterCells > 0 ? letterCells : null, solutionHash: hash ?? null, source };
}

/** Entries of the publisher-maintained pool for a language/level (empty when the document is missing). */
export async function readMatchPool(db: Db, lang: string, level: number): Promise<PuzzleRef[]> {
  const doc = await db.getDoc(matchPoolPath(lang, level));
  const puzzles = getField(doc.data, 'puzzles');
  if (!Array.isArray(puzzles)) return [];
  const out: PuzzleRef[] = [];
  for (const p of puzzles) {
    if (typeof p === 'string') out.push({ puzzleId: p, letterCells: null, solutionHash: null, source: 'pool' });
    else if (typeof p === 'object' && p !== null) {
      const ref = refFrom(p as DocData, 'pool');
      if (ref) out.push(ref);
    }
  }
  return out;
}

const DAILY_SAMPLE = 200;

async function dailiesOf(db: Db, lang: string, level?: number): Promise<PuzzleRef[]> {
  const filters: Filter[] = [{ field: 'lang', op: '==', value: lang }];
  if (level !== undefined) filters.push({ field: 'level', op: '==', value: level });
  const docs = await db.queryDocs('dailies', filters, { limit: DAILY_SAMPLE });
  return docs.map((d) => refFrom(d.data, 'daily')).filter((r): r is PuzzleRef => r !== undefined);
}

function choose<T>(items: readonly T[], random: RandomSource): T | undefined {
  if (items.length === 0) return undefined;
  return items[Math.min(items.length - 1, Math.floor(random() * items.length))];
}

/** A random puzzle for a random match: pool entries with a known size first, then dailies of the level, then any daily of the language. */
export async function pickRandomPuzzle(db: Db, lang: string, level: number, random: RandomSource): Promise<PuzzleRef | undefined> {
  const pool = (await readMatchPool(db, lang, level)).filter((p) => p.letterCells !== null);
  const fromPool = choose(pool, random);
  if (fromPool) return fromPool;
  const sameLevel = await dailiesOf(db, lang, level);
  const fromLevel = choose(sameLevel, random);
  if (fromLevel) return fromLevel;
  return choose(await dailiesOf(db, lang), random);
}

/** Looks a specific puzzle id up (pool of the level if given, then dailies, then the publish index). */
export async function resolvePuzzle(db: Db, lang: string, puzzleId: string, level?: number): Promise<PuzzleRef | undefined> {
  if (level !== undefined) {
    const pooled = (await readMatchPool(db, lang, level)).find((p) => p.puzzleId === puzzleId);
    if (pooled) return pooled;
  }
  const dailies = await db.queryDocs('dailies', [{ field: 'puzzleId', op: '==', value: puzzleId }], { limit: 1 });
  const daily = dailies[0] ? refFrom(dailies[0].data, 'daily') : undefined;
  if (daily) return daily;
  const indexed = await db.getDoc(puzzleIndexPath(puzzleId));
  return indexed.exists ? refFrom(indexed.data, 'index') : undefined;
}
