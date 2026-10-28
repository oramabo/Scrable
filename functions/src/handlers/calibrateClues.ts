/**
 * Nightly job (stub of the §5.3 self-calibration): aggregates
 * `telemetry/wordSolved/events/*` per clue into `clueStats/{clueId}` with the
 * sample size, the median relative solve time and the hint rate.
 */
import type { Db, DocData } from '../lib/firestore';

export const WORD_SOLVED_COLLECTION = 'telemetry/wordSolved/events';
export const CLUE_STATS_COLLECTION = 'clueStats';

export interface WordSolvedEvent {
  clueId: string;
  /** Time from word focus to solve, normalised by the player's skill (seconds). */
  relTime: number;
  hinted: boolean;
  lang?: string;
}

export interface ClueStats {
  n: number;
  medianRelTime: number;
  hintRate: number;
  lang?: string;
}

export function parseWordSolvedEvent(data: DocData | undefined): WordSolvedEvent | undefined {
  if (!data) return undefined;
  const clueId = data['clueId'];
  const relTime = data['relTime'];
  const hinted = data['hinted'];
  if (typeof clueId !== 'string' || clueId.length === 0 || clueId.length > 128) return undefined;
  if (typeof relTime !== 'number' || !Number.isFinite(relTime) || relTime < 0) return undefined;
  if (typeof hinted !== 'boolean') return undefined;
  const lang = data['lang'];
  return { clueId, relTime, hinted, lang: typeof lang === 'string' ? lang : undefined };
}

export function median(sorted: readonly number[]): number {
  const n = sorted.length;
  if (n === 0) return 0;
  const mid = Math.floor(n / 2);
  return n % 2 === 1 ? (sorted[mid] as number) : ((sorted[mid - 1] as number) + (sorted[mid] as number)) / 2;
}

/** Pure aggregation: events → per-clue stats. */
export function aggregateWordSolved(events: Iterable<WordSolvedEvent>): Map<string, ClueStats> {
  const buckets = new Map<string, { times: number[]; hinted: number; lang?: string }>();
  for (const e of events) {
    let b = buckets.get(e.clueId);
    if (!b) {
      b = { times: [], hinted: 0, lang: e.lang };
      buckets.set(e.clueId, b);
    }
    b.times.push(e.relTime);
    if (e.hinted) b.hinted++;
    if (b.lang === undefined && e.lang !== undefined) b.lang = e.lang;
  }
  const out = new Map<string, ClueStats>();
  for (const [clueId, b] of buckets) {
    b.times.sort((x, y) => x - y);
    const stats: ClueStats = { n: b.times.length, medianRelTime: median(b.times), hintRate: b.hinted / b.times.length };
    if (b.lang !== undefined) stats.lang = b.lang;
    out.set(clueId, stats);
  }
  return out;
}

export interface CalibrateResult {
  events: number;
  skipped: number;
  clues: number;
}

export async function calibrateClues(db: Db, now: number, pageSize = 500): Promise<CalibrateResult> {
  const events: WordSolvedEvent[] = [];
  let skipped = 0;
  let startAfterId: string | undefined;
  for (;;) {
    const page = await db.queryDocs(WORD_SOLVED_COLLECTION, [], { limit: pageSize, startAfterId });
    for (const doc of page) {
      const e = parseWordSolvedEvent(doc.data);
      if (e) events.push(e);
      else skipped++;
    }
    if (page.length < pageSize) break;
    startAfterId = page[page.length - 1]?.id;
  }
  const stats = aggregateWordSolved(events);
  for (const [clueId, s] of stats) {
    await db.setDoc(`${CLUE_STATS_COLLECTION}/${clueId}`, { ...s, updatedAt: now }, { merge: true });
  }
  return { events: events.length, skipped, clues: stats.size };
}
