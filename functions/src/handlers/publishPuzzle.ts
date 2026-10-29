/**
 * `publishPuzzle` callable (admin): validates a puzzle against
 * schema/puzzle.schema.json, verifies its checksum, uploads the immutable
 * JSON to Storage and records it in Firestore (`dailies/*` for dailies and
 * the `manifests/{lang}_daily|_packs` source documents).
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { type Db, type DocData, getField, readNumber } from '../lib/firestore';
import { decodeLetterSymbols, letterCellCount, type PuzzleLike, solutionHash as computeSolutionHash, verifyChecksum } from '../lib/puzzleCodec';
import { puzzleIndexPath } from '../lib/puzzleLookup';
import { CACHE_IMMUTABLE, type ObjectStore } from '../lib/storage';
import { validate } from '../lib/validate';
import { dailyDocPath } from './submitDaily';

export interface PublishDeps {
  db: Db;
  storage: ObjectStore;
}

/** Pack display title: plain string or a map of UI language to string (`{he, en}`), as `chetz_gen` writes it. */
export type PackTitle = string | Record<string, string>;

export interface PackMetaInput {
  /** 1-based position of the pack within its level (default: trailing number of the pack id, e.g. `he-l1-p03` → 3). */
  index?: number;
  title?: PackTitle;
  /** Default: the first pack of a level is free. */
  free?: boolean;
}

export interface PublishInput {
  puzzle: unknown;
  lang: string;
  /** Optional publisher-computed `PuzzleCodec.solutionHash`; cross-checked against the server's own computation. */
  solutionHash?: string;
  pack?: PackMetaInput;
}

export interface PublishResult {
  id: string;
  kind: string;
  lang: string;
  path: string;
  url: string;
  checksum: string;
  version: number;
  letterCells: number;
  solutionHash: string;
  dailyDoc?: string;
  manifestDoc: string;
}

export function dailyManifestDocPath(lang: string): string {
  return `manifests/${lang}_daily`;
}
export function packsManifestDocPath(lang: string): string {
  return `manifests/${lang}_packs`;
}

export function storagePathFor(p: PuzzleLike): string {
  if (p.kind === 'daily' && p.daily) return `puzzles/${p.lang}/daily/${p.daily.variant}/${p.daily.date}.v${p.meta.version}.json`;
  if (p.kind === 'pack' && p.pack) return `puzzles/${p.lang}/packs/${p.pack.id}/${packFileStem(p.pack.index)}.v${p.meta.version}.json`;
  throw new HttpsError('invalid-argument', `only daily and pack puzzles are published to the CDN (kind=${p.kind}); tutorial and practice puzzles ship inside the app`);
}

/** Zero-padded puzzle number inside a pack, matching the content pipeline's file names (`01.json` → `01.v1.json`). */
export function packFileStem(index: number): string {
  return String(index).padStart(2, '0');
}

/** `he-l1-p03` → 3 */
export function inferPackIndex(packId: string): number | undefined {
  const m = /(\d{1,4})$/.exec(packId);
  return m ? Number(m[1]) : undefined;
}

function bad(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

function isPackTitle(v: unknown): v is PackTitle {
  if (typeof v === 'string') return true;
  return typeof v === 'object' && v !== null && !Array.isArray(v) && Object.values(v as Record<string, unknown>).every((t) => typeof t === 'string');
}

function parsePublishInput(input: unknown): PublishInput {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) bad('expected an object with `puzzle` and `lang`');
  const o = input as Record<string, unknown>;
  const puzzle = o['puzzle'];
  if (typeof puzzle !== 'object' || puzzle === null || Array.isArray(puzzle)) bad('`puzzle` must be the puzzle JSON object');
  const lang = o['lang'];
  if (lang !== 'he' && lang !== 'en') bad('`lang` must be "he" or "en"');
  const solutionHash = o['solutionHash'];
  if (solutionHash !== undefined && (typeof solutionHash !== 'string' || !/^[0-9a-f]{64}$/.test(solutionHash))) bad('`solutionHash` must be a lowercase hex sha256');
  const packRaw = o['pack'];
  let pack: PackMetaInput | undefined;
  if (packRaw !== undefined) {
    if (typeof packRaw !== 'object' || packRaw === null || Array.isArray(packRaw)) bad('`pack` must be an object');
    const pr = packRaw as Record<string, unknown>;
    pack = {};
    if (pr['index'] !== undefined) {
      if (typeof pr['index'] !== 'number' || !Number.isInteger(pr['index']) || pr['index'] < 1) bad('`pack.index` must be a positive integer');
      pack.index = pr['index'];
    }
    if (pr['title'] !== undefined) pack.title = parsePackTitle(pr['title']);
    if (pr['free'] !== undefined) {
      if (typeof pr['free'] !== 'boolean') bad('`pack.free` must be a boolean');
      pack.free = pr['free'];
    }
  }
  return { puzzle, lang, solutionHash: solutionHash as string | undefined, pack };
}

function parsePackTitle(raw: unknown): PackTitle {
  if (typeof raw === 'string') {
    if (raw.length > 200) bad('`pack.title` must be at most 200 characters');
    return raw;
  }
  if (typeof raw === 'object' && raw !== null && !Array.isArray(raw)) {
    const entries = Object.entries(raw as Record<string, unknown>);
    if (entries.length === 0) bad('`pack.title` map must not be empty');
    const out: Record<string, string> = {};
    for (const [lang, text] of entries) {
      if (!/^[a-z]{2}$/.test(lang) || typeof text !== 'string' || text.length > 200) bad('`pack.title` must map two-letter language codes to strings of at most 200 characters');
      out[lang] = text;
    }
    return out;
  }
  return bad('`pack.title` must be a string or a {lang: string} map');
}

/** Schema + structural + checksum validation; returns the typed puzzle, the letter-cell count and the solution hash. */
export function verifyPublishablePuzzle(puzzle: unknown, lang: string, providedHash?: string): { puzzle: PuzzleLike; letterCells: number; solutionHash: string } {
  const schema = validate('puzzle', puzzle);
  if (!schema.ok) bad(`puzzle does not match schema/puzzle.schema.json: ${schema.errors.join('; ')}`);
  const p = puzzle as PuzzleLike;
  if (p.lang !== lang) bad(`puzzle.lang "${p.lang}" does not match lang "${lang}"`);
  if (p.layout.length !== p.grid.rows || p.layout.some((row) => row.length !== p.grid.cols)) bad('layout does not match grid dimensions');
  if (typeof p.meta.checksum !== 'string') bad('meta.checksum is required: run the puzzle through PuzzleCodec.withChecksum before publishing');
  const letterCells = letterCellCount(p.layout);
  let letters: number[];
  try {
    letters = decodeLetterSymbols(p);
  } catch (err) {
    bad(`solution cannot be decoded: ${err instanceof Error ? err.message : String(err)}`);
  }
  if (letters.length !== letterCells) bad(`solution has ${letters.length} symbols for ${letterCells} letter cells`);
  const check = verifyChecksum(p);
  if (!check.ok) bad(`meta.checksum ${check.actual ?? ''} does not match the recomputed ${check.expected}`);
  const hash = computeSolutionHash(p);
  if (providedHash !== undefined && providedHash !== hash) bad('solutionHash does not match the puzzle solution');
  return { puzzle: p, letterCells, solutionHash: hash };
}

export async function publishPuzzle(deps: PublishDeps, input: unknown, now: number, actorUid: string): Promise<PublishResult> {
  const parsed = parsePublishInput(input);
  const { puzzle: p, letterCells, solutionHash } = verifyPublishablePuzzle(parsed.puzzle, parsed.lang, parsed.solutionHash);
  const checksum = p.meta.checksum as string;
  const path = storagePathFor(p);
  const url = deps.storage.publicUrl(path);
  await deps.storage.putJson(path, p, { cacheControl: CACHE_IMMUTABLE });
  const publishedAt = new Date(now).toISOString();

  // Lookup record for the multiplayer handlers (match / co-op puzzle resolution by id).
  await deps.db.setDoc(puzzleIndexPath(p.id), {
    puzzleId: p.id,
    lang: p.lang,
    kind: p.kind,
    level: p.level,
    letterCells,
    solutionHash,
    checksum,
    version: p.meta.version,
    path,
    publishedAt: now,
  });

  if (p.kind === 'daily' && p.daily) {
    const dailyDoc = dailyDocPath(p.lang, p.daily.date, p.daily.variant);
    await deps.db.setDoc(dailyDoc, {
      puzzleId: p.id,
      lang: p.lang,
      date: p.daily.date,
      variant: p.daily.variant,
      level: p.level,
      letterCells,
      solutionHash,
      checksum,
      version: p.meta.version,
      path,
      url,
      publishedAt: now,
      publishedBy: actorUid,
    });
    const manifestDoc = dailyManifestDocPath(p.lang);
    const entry: DocData = { date: p.daily.date, variant: p.daily.variant, id: p.id, path, url, checksum, version: p.meta.version, level: p.level, publishedAt };
    await deps.db.setDoc(manifestDoc, { lang: p.lang, updatedAt: now, entries: { [`${p.daily.date}_${p.daily.variant}`]: entry } }, { merge: true });
    return { id: p.id, kind: p.kind, lang: p.lang, path, url, checksum, version: p.meta.version, letterCells, solutionHash, dailyDoc, manifestDoc };
  }

  if (p.kind === 'pack' && p.pack) {
    const manifestDoc = packsManifestDocPath(p.lang);
    const current = await deps.db.getDoc(manifestDoc);
    const existing = getField(current.data, `packs.${p.pack.id}`) as DocData | undefined;
    const existingIndex = existing ? readNumber(existing, 'index', 0) : 0;
    const index = parsed.pack?.index ?? (existingIndex > 0 ? existingIndex : inferPackIndex(p.pack.id) ?? 1);
    const existingTitle = existing ? getField(existing, 'title') : undefined;
    const title: PackTitle = parsed.pack?.title ?? (isPackTitle(existingTitle) ? existingTitle : undefined) ?? p.title ?? p.pack.id;
    const existingFree = existing ? getField(existing, 'free') : undefined;
    const free = parsed.pack?.free ?? (typeof existingFree === 'boolean' ? existingFree : index === 1);
    const puzzleKey = String(p.pack.index).padStart(3, '0');
    await deps.db.setDoc(
      manifestDoc,
      {
        lang: p.lang,
        updatedAt: now,
        packs: {
          [p.pack.id]: {
            id: p.pack.id,
            lang: p.lang,
            level: p.level,
            index,
            title,
            free,
            updatedAt: now,
            puzzles: {
              [puzzleKey]: { index: p.pack.index, id: p.id, path, url, checksum, version: p.meta.version, difficulty: p.difficulty.score, words: p.words.length, publishedAt },
            },
          },
        },
      },
      { merge: true },
    );
    return { id: p.id, kind: p.kind, lang: p.lang, path, url, checksum, version: p.meta.version, letterCells, solutionHash, manifestDoc };
  }

  // storagePathFor already rejected other kinds.
  throw new HttpsError('internal', 'unreachable: unsupported puzzle kind');
}
