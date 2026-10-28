import { isoDate } from '../lib/time';

export interface ServerTime {
  nowMs: number;
  /** UTC calendar date `YYYY-MM-DD`; the app derives the daily's date from it, not from the device clock. */
  date: string;
}

export function serverTime(now: number): ServerTime {
  return { nowMs: now, date: isoDate(now) };
}
