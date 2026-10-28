export const DAY_MS = 86_400_000;

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** `YYYY-MM-DD` in UTC for a millisecond timestamp. */
export function isoDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** Parses a strict `YYYY-MM-DD` string into the UTC midnight timestamp, or undefined. */
export function parseIsoDate(date: string): number | undefined {
  const m = ISO_DATE.exec(date);
  if (!m) return undefined;
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isoDate(ms) === date ? ms : undefined;
}

export function isValidIsoDate(date: unknown): date is string {
  return typeof date === 'string' && parseIsoDate(date) !== undefined;
}

/** Signed whole days from `a` to `b` (both `YYYY-MM-DD`). */
export function daysBetween(a: string, b: string): number {
  const ta = parseIsoDate(a);
  const tb = parseIsoDate(b);
  if (ta === undefined || tb === undefined) throw new Error(`invalid date: ${ta === undefined ? a : b}`);
  return Math.round((tb - ta) / DAY_MS);
}

export function addDays(date: string, days: number): string {
  const t = parseIsoDate(date);
  if (t === undefined) throw new Error(`invalid date: ${date}`);
  return isoDate(t + days * DAY_MS);
}
