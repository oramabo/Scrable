/**
 * `rebuildManifests` callable (admin): turns the Firestore source documents
 * `manifests/{lang}_daily` and `manifests/{lang}_packs` into the CDN files
 * `manifests/{lang}/daily.json`, `manifests/{lang}/packs.json` and one pack
 * file `puzzles/{lang}/packs/{packId}/pack.v1.json` per pack, in the same shape
 * `chetz_gen manifest` produces (urls relative to the CDN root, which the app
 * prefixes with its configured base URL), each validated against
 * schema/*-manifest.schema.json before upload.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { type Db, type DocData, getField } from '../lib/firestore';
import { canonicalJson, sha256Hex } from '../lib/puzzleCodec';
import { CACHE_SHORT, type ObjectStore } from '../lib/storage';
import { addDays, isoDate } from '../lib/time';
import { type SchemaName, validate } from '../lib/validate';
import { dailyManifestDocPath, packsManifestDocPath, type PackTitle } from './publishPuzzle';

export const DAILY_MANIFEST_PAST_DAYS = 365;
export const DAILY_MANIFEST_FUTURE_DAYS = 3;
export const MANIFEST_FORMAT_VERSION = 1;

export interface RebuildDeps {
  db: Db;
  storage: ObjectStore;
}

export interface DailyManifestEntry {
  date: string;
  variant: string;
  id: string;
  url: string;
  checksum: string;
  version: number;
}

export interface DailyManifest {
  version: number;
  generatedAt: string;
  lang: string;
  entries: DailyManifestEntry[];
}

export interface PackPuzzleRef {
  id: string;
  index: number;
  url: string;
  checksum: string;
  version: number;
  difficulty?: number;
  words?: number;
}

export interface PackMeta {
  id: string;
  level: number;
  index: number;
  title: PackTitle;
  free: boolean;
}

/** `puzzles/{lang}/packs/{packId}/pack.v1.json` */
export interface PackFile extends PackMeta {
  version: number;
  generatedAt: string;
  lang: string;
  puzzleCount: number;
  puzzles: PackPuzzleRef[];
  /** sha256 of the canonical JSON of `puzzles`. */
  checksum: string;
}

export interface PacksManifestEntry extends PackMeta {
  lang: string;
  puzzleCount: number;
  url: string;
  checksum: string;
  puzzles: PackPuzzleRef[];
}

export interface PacksManifest {
  version: number;
  generatedAt: string;
  lang: string;
  packs: PacksManifestEntry[];
}

export interface RebuildResult {
  lang: string;
  dailyEntries: number;
  packs: number;
  files: string[];
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
function str(o: Record<string, unknown>, key: string): string {
  const v = o[key];
  return typeof v === 'string' ? v : '';
}
function num(o: Record<string, unknown>, key: string, fallback = 0): number {
  const v = o[key];
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

/** CDN-relative path of a published file: the stored `path`, or the legacy absolute `url` when no path was recorded. */
function cdnPath(o: Record<string, unknown>): string {
  const path = str(o, 'path');
  return path.length > 0 ? path : str(o, 'url');
}

function parseLang(input: unknown): string {
  const lang = isRecord(input) ? input['lang'] : undefined;
  if (lang !== 'he' && lang !== 'en') throw new HttpsError('invalid-argument', '`lang` must be "he" or "en"');
  return lang;
}

function assertValid(name: SchemaName, data: unknown): void {
  const result = validate(name, data);
  if (!result.ok) throw new HttpsError('internal', `generated ${name} does not match its schema: ${result.errors.join('; ')}`);
}

/** Daily manifest for the window [today − 365, today + 3] from the Firestore source document. */
export function buildDailyManifest(doc: DocData | undefined, lang: string, now: number): DailyManifest {
  const today = isoDate(now);
  const from = addDays(today, -DAILY_MANIFEST_PAST_DAYS);
  const to = addDays(today, DAILY_MANIFEST_FUTURE_DAYS);
  const map = getField(doc, 'entries');
  const entries: DailyManifestEntry[] = Object.values(isRecord(map) ? map : {})
    .filter(isRecord)
    .map((e) => ({ date: str(e, 'date'), variant: str(e, 'variant'), id: str(e, 'id'), url: cdnPath(e), checksum: str(e, 'checksum'), version: num(e, 'version', 1) }))
    .filter((e) => e.date >= from && e.date <= to)
    .sort((a, b) => a.date.localeCompare(b.date) || a.variant.localeCompare(b.variant));
  return { version: MANIFEST_FORMAT_VERSION, generatedAt: new Date(now).toISOString(), lang, entries };
}

/** Pack metadata and ordered puzzle references from the Firestore source document. */
export function readPacks(doc: DocData | undefined): Array<{ meta: PackMeta; puzzles: PackPuzzleRef[] }> {
  const map = getField(doc, 'packs');
  const packs = Object.values(isRecord(map) ? map : {}).filter(isRecord).map((p) => {
    const puzzlesMap = p['puzzles'];
    const puzzles: PackPuzzleRef[] = Object.values(isRecord(puzzlesMap) ? puzzlesMap : {})
      .filter(isRecord)
      .map((q) => {
        const ref: PackPuzzleRef = { id: str(q, 'id'), index: num(q, 'index', 0), url: cdnPath(q), checksum: str(q, 'checksum'), version: num(q, 'version', 1) };
        if (typeof q['difficulty'] === 'number') ref.difficulty = q['difficulty'];
        if (typeof q['words'] === 'number') ref.words = q['words'];
        return ref;
      })
      .sort((a, b) => a.index - b.index);
    const rawTitle = p['title'];
    const title: PackTitle = typeof rawTitle === 'string' ? rawTitle : isRecord(rawTitle) ? Object.fromEntries(Object.entries(rawTitle).filter((e): e is [string, string] => typeof e[1] === 'string')) : str(p, 'id');
    const meta: PackMeta = { id: str(p, 'id'), level: num(p, 'level', 1), index: num(p, 'index', 1), title, free: p['free'] === true };
    return { meta, puzzles };
  });
  return packs.sort((a, b) => a.meta.level - b.meta.level || a.meta.index - b.meta.index);
}

export function packFilePath(lang: string, packId: string): string {
  return `puzzles/${lang}/packs/${packId}/pack.v1.json`;
}

export async function rebuildManifests(deps: RebuildDeps, input: unknown, now: number): Promise<RebuildResult> {
  const lang = parseLang(input);
  const generatedAt = new Date(now).toISOString();
  const files: string[] = [];

  const dailyDoc = await deps.db.getDoc(dailyManifestDocPath(lang));
  const daily = buildDailyManifest(dailyDoc.data, lang, now);
  assertValid('daily-manifest', daily);
  const dailyPath = `manifests/${lang}/daily.json`;
  await deps.storage.putJson(dailyPath, daily, { cacheControl: CACHE_SHORT });
  files.push(dailyPath);

  const packsDoc = await deps.db.getDoc(packsManifestDocPath(lang));
  const packs: PacksManifestEntry[] = [];
  for (const { meta, puzzles } of readPacks(packsDoc.data)) {
    const path = packFilePath(lang, meta.id);
    const checksum = `sha256:${sha256Hex(canonicalJson(puzzles))}`;
    const packFile: PackFile = { ...meta, version: MANIFEST_FORMAT_VERSION, generatedAt, lang, puzzleCount: puzzles.length, puzzles, checksum };
    await deps.storage.putJson(path, packFile, { cacheControl: CACHE_SHORT });
    files.push(path);
    packs.push({ ...meta, lang, puzzleCount: puzzles.length, url: path, checksum, puzzles });
  }
  const packsManifest: PacksManifest = { version: MANIFEST_FORMAT_VERSION, generatedAt, lang, packs };
  assertValid('packs-manifest', packsManifest);
  const packsPath = `manifests/${lang}/packs.json`;
  await deps.storage.putJson(packsPath, packsManifest, { cacheControl: CACHE_SHORT });
  files.push(packsPath);

  return { lang, dailyEntries: daily.entries.length, packs: packs.length, files };
}
