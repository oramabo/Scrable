/**
 * Season-pass calendar. Seasons are consecutive 42-day (6-week) windows in
 * UTC; season 1 starts on Monday 2026-11-02. The id is
 * `${year of the season's first day}-S${n}` with `n` the global 1-based
 * season number, so `2026-S1` (2026-11-02 … 2026-12-13), `2026-S2`
 * (2026-12-14 … 2027-01-24), `2027-S3` (2027-01-25 … ), ... The year prefix
 * only groups and sorts; `n` never resets. Dates before season 1 have no
 * season (no season points are awarded for them). `packages/core` mirrors
 * this rule for the app.
 */
import { addDays, DAY_MS, isoDate, parseIsoDate } from './time';

export const SEASON_EPOCH_DATE = '2026-11-02';
export const SEASON_LENGTH_DAYS = 42;

const SEASON_ID = /^(\d{4})-S([1-9]\d{0,4})$/;

export interface SeasonBounds {
  id: string;
  /** Global 1-based season number. */
  n: number;
  /** First day (inclusive), `YYYY-MM-DD` UTC. */
  start: string;
  /** Last day (inclusive). */
  end: string;
  /** `[startMs, endMs)` in milliseconds since the epoch. */
  startMs: number;
  endMs: number;
}

function epochMs(): number {
  return parseIsoDate(SEASON_EPOCH_DATE) as number;
}

function boundsOfIndex(n: number): SeasonBounds {
  const startMs = epochMs() + (n - 1) * SEASON_LENGTH_DAYS * DAY_MS;
  const endMs = startMs + SEASON_LENGTH_DAYS * DAY_MS;
  const start = isoDate(startMs);
  return { id: `${start.slice(0, 4)}-S${n}`, n, start, end: addDays(start, SEASON_LENGTH_DAYS - 1), startMs, endMs };
}

/** Season number (1-based) containing a `YYYY-MM-DD` date, or undefined before season 1 / for an invalid date. */
export function seasonNumberFor(dateIso: string): number | undefined {
  const t = parseIsoDate(dateIso);
  if (t === undefined) return undefined;
  const idx = Math.floor((t - epochMs()) / (SEASON_LENGTH_DAYS * DAY_MS));
  return idx < 0 ? undefined : idx + 1;
}

/** Season id (`2026-S1`) for a `YYYY-MM-DD` UTC date; undefined before 2026-11-02. */
export function seasonIdFor(dateIso: string): string | undefined {
  const n = seasonNumberFor(dateIso);
  return n === undefined ? undefined : boundsOfIndex(n).id;
}

/** Season id for a millisecond timestamp (UTC date). */
export function seasonIdAt(ms: number): string | undefined {
  return seasonIdFor(isoDate(ms));
}

/** Bounds of a season by id (`2026-S1`) or by number; undefined when the id is malformed or its year prefix is wrong. */
export function seasonBounds(season: string | number): SeasonBounds | undefined {
  if (typeof season === 'number') {
    return Number.isInteger(season) && season >= 1 ? boundsOfIndex(season) : undefined;
  }
  const m = SEASON_ID.exec(season);
  if (!m) return undefined;
  const bounds = boundsOfIndex(Number(m[2]));
  return bounds.id === season ? bounds : undefined;
}

/** Bounds of the season containing a date; undefined before season 1. */
export function seasonBoundsFor(dateIso: string): SeasonBounds | undefined {
  const n = seasonNumberFor(dateIso);
  return n === undefined ? undefined : boundsOfIndex(n);
}
