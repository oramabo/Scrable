/**
 * TypeScript port of the parts of packages/core PuzzleCodec the backend
 * needs: decoding the obfuscated solution, the canonical-JSON checksum and the
 * leaderboard solution hash. Must stay byte-identical with
 * packages/core/lib/src/model/puzzle_codec.dart.
 */
import { createHash } from 'node:crypto';

/** Mixed into the solution keystream; not a secret (same constant as the Dart codec). */
export const DEFAULT_SALT = 'chetz-v1';

export interface PuzzleSolution {
  enc: 'xor1' | 'plain';
  data: string | number[];
}

/** The subset of the puzzle JSON the codec functions read. */
export interface PuzzleLike {
  id: string;
  kind: string;
  lang: string;
  level: number;
  title?: string;
  grid: { rows: number; cols: number; colOrigin: string };
  layout: string[];
  /** Format 1: one object per word. */
  words?: unknown[];
  /** Format 2 (`schemaVersion: 2`): one compact array per clue, i.e. per word. */
  clues?: unknown[];
  difficulty: { score: number; band: string } & Record<string, unknown>;
  solution: PuzzleSolution;
  meta: { version: number; checksum?: string } & Record<string, unknown>;
  daily?: { date: string; variant: string };
  pack?: { id: string; index: number };
  [key: string]: unknown;
}

/** Number of words in either puzzle format. */
export function wordCount(puzzle: PuzzleLike): number {
  return (puzzle.clues ?? puzzle.words ?? []).length;
}

export function letterCellCount(layout: readonly string[]): number {
  let n = 0;
  for (const row of layout) for (const ch of row) if (ch === 'L') n++;
  return n;
}

function keystreamXor(id: string, data: Uint8Array, salt: string): Uint8Array {
  const out = new Uint8Array(data.length);
  let counter = 0;
  let offset = 0;
  while (offset < data.length) {
    const block = createHash('sha256').update(`${id}|${salt}|${counter}`, 'utf8').digest();
    for (let i = 0; i < block.length && offset < data.length; i++, offset++) {
      out[offset] = data[offset]! ^ block[i]!;
    }
    counter++;
  }
  return out;
}

/** Symbol ids of the letter cells in row-major order. */
export function decodeLetterSymbols(puzzle: PuzzleLike, salt = DEFAULT_SALT): number[] {
  const { solution } = puzzle;
  if (solution.enc === 'plain') {
    if (!Array.isArray(solution.data)) throw new Error('plain solution data must be an array');
    return solution.data.map((v) => {
      if (!Number.isInteger(v) || v < 0) throw new Error('plain solution contains a non-integer symbol');
      return v;
    });
  }
  if (solution.enc === 'xor1') {
    if (typeof solution.data !== 'string') throw new Error('xor1 solution data must be a base64 string');
    const bytes = new Uint8Array(Buffer.from(solution.data, 'base64'));
    return Array.from(keystreamXor(puzzle.id, bytes, salt));
  }
  throw new Error(`unknown solution encoding ${String((solution as { enc: unknown }).enc)}`);
}

/** Deterministic JSON identical to `PuzzleCodec.canonicalJson`: sorted keys, no whitespace, integral numbers without a fraction. */
export function canonicalJson(value: unknown): string {
  const parts: string[] = [];
  writeCanonical(value, parts);
  return parts.join('');
}

function writeCanonical(value: unknown, out: string[]): void {
  if (value === null || value === undefined) {
    out.push('null');
  } else if (Array.isArray(value)) {
    out.push('[');
    value.forEach((v, i) => {
      if (i > 0) out.push(',');
      writeCanonical(v, out);
    });
    out.push(']');
  } else if (typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const keys = Object.keys(obj).sort();
    out.push('{');
    keys.forEach((k, i) => {
      if (i > 0) out.push(',');
      out.push(JSON.stringify(k), ':');
      writeCanonical(obj[k], out);
    });
    out.push('}');
  } else if (typeof value === 'number') {
    if (Number.isInteger(value) && Math.abs(value) < 1e15) out.push(String(value));
    else out.push(dartDoubleToString(value));
  } else {
    out.push(JSON.stringify(value));
  }
}

/** Dart `double.toString()` for non-integral finite values: shortest round-trip, matching JS except for exponent formatting. */
function dartDoubleToString(v: number): string {
  if (!Number.isFinite(v)) throw new Error('non-finite number in canonical JSON');
  const s = String(v); // JS and Dart both use the shortest round-trip representation
  // Dart writes 1e+21 as "1e+21" and 1e-7 as "1e-7" like JS; nothing to adjust.
  return s;
}

/** `sha256:<hex>` over the canonical JSON of the puzzle with a plain solution and `meta.checksum` removed. */
export function puzzleChecksum(puzzle: PuzzleLike, salt = DEFAULT_SALT): string {
  const letters = decodeLetterSymbols(puzzle, salt);
  const meta: Record<string, unknown> = { ...puzzle.meta };
  delete meta['checksum'];
  const canonical: Record<string, unknown> = { ...puzzle, solution: { enc: 'plain', data: letters }, meta };
  return `sha256:${createHash('sha256').update(canonicalJson(canonical), 'utf8').digest('hex')}`;
}

/** Hash of the normalised solution used by `submitDaily` (`PuzzleCodec.solutionHash`). */
export function solutionHash(puzzle: PuzzleLike, salt = DEFAULT_SALT): string {
  const letters = decodeLetterSymbols(puzzle, salt);
  return createHash('sha256').update(`${puzzle.id}|${letters.join(',')}`, 'utf8').digest('hex');
}

/** Checks the embedded checksum, returning the recomputed value on mismatch. */
export function verifyChecksum(puzzle: PuzzleLike, salt = DEFAULT_SALT): { ok: boolean; expected: string; actual: string | undefined } {
  const expected = puzzleChecksum(puzzle, salt);
  return { ok: puzzle.meta.checksum === expected, expected, actual: puzzle.meta.checksum };
}

export function sha256Hex(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}
