/**
 * `submitDaily` callable: plausibility-checked leaderboard submission for a
 * daily puzzle. One entry per uid per daily; the score is time plus penalties.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import { DAILY_MIN_MS_PER_LETTER, DAILY_SUBMISSION_WINDOW_DAYS, MODE_TIME_FACTOR, PENALTY_MS } from '../economy';
import { type Db, readNumber, readString } from '../lib/firestore';
import { daysBetween, isoDate, isValidIsoDate } from '../lib/time';

export type PlayMode = 'relaxed' | 'normal' | 'newspaper';
export type Lang = 'he' | 'en';
export type DailyVariant = 'easy' | 'hard';

export interface SubmitDailyInput {
  puzzleId: string;
  lang: Lang;
  date: string;
  variant: DailyVariant;
  elapsedMs: number;
  lettersRevealed: number;
  wordsRevealed: number;
  checksUsed: number;
  mode: PlayMode;
  solutionHash: string;
}

export interface SubmitDailyResult {
  score: number;
  rank: number;
}

const PUZZLE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const SHA256_HEX = /^[0-9a-f]{64}$/;
const MAX_ELAPSED_MS = 7 * 24 * 3_600_000;
const MAX_COUNT = 10_000;

function bad(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

function intField(o: Record<string, unknown>, key: string, max: number): number {
  const v = o[key];
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > max) bad(`${key} must be an integer between 0 and ${max}`);
  return v;
}

export function parseSubmitDailyInput(input: unknown): SubmitDailyInput {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) bad('expected an object');
  const o = input as Record<string, unknown>;
  const puzzleId = o['puzzleId'];
  if (typeof puzzleId !== 'string' || !PUZZLE_ID.test(puzzleId)) bad('puzzleId is invalid');
  const lang = o['lang'];
  if (lang !== 'he' && lang !== 'en') bad('lang must be "he" or "en"');
  const date = o['date'];
  if (!isValidIsoDate(date)) bad('date must be YYYY-MM-DD');
  const variant = o['variant'];
  if (variant !== 'easy' && variant !== 'hard') bad('variant must be "easy" or "hard"');
  const mode = o['mode'];
  if (mode !== 'relaxed' && mode !== 'normal' && mode !== 'newspaper') bad('mode must be relaxed, normal or newspaper');
  const solutionHash = o['solutionHash'];
  if (typeof solutionHash !== 'string' || !SHA256_HEX.test(solutionHash)) bad('solutionHash must be a lowercase hex sha256');
  return {
    puzzleId,
    lang,
    date,
    variant,
    mode,
    solutionHash,
    elapsedMs: intField(o, 'elapsedMs', MAX_ELAPSED_MS),
    lettersRevealed: intField(o, 'lettersRevealed', MAX_COUNT),
    wordsRevealed: intField(o, 'wordsRevealed', MAX_COUNT),
    checksUsed: intField(o, 'checksUsed', MAX_COUNT),
  };
}

/** score = elapsed + 20 s per revealed letter + 60 s per revealed word + 15 s per check + mode factor × elapsed (ms, rounded). */
export function computeScore(i: Pick<SubmitDailyInput, 'elapsedMs' | 'lettersRevealed' | 'wordsRevealed' | 'checksUsed' | 'mode'>): number {
  const penalties = PENALTY_MS.letterRevealed * i.lettersRevealed + PENALTY_MS.wordRevealed * i.wordsRevealed + PENALTY_MS.checkUsed * i.checksUsed;
  return Math.round(i.elapsedMs + penalties + MODE_TIME_FACTOR[i.mode] * i.elapsedMs);
}

export function dailyKey(lang: string, date: string, variant: string): string {
  return `${lang}_${date}_${variant}`;
}
export function dailyDocPath(lang: string, date: string, variant: string): string {
  return `dailies/${dailyKey(lang, date, variant)}`;
}
export function leaderboardEntriesPath(lang: string, date: string, variant: string): string {
  return `leaderboards/${dailyKey(lang, date, variant)}/entries`;
}

export async function submitDaily(db: Db, uid: string, input: unknown, now: number): Promise<SubmitDailyResult> {
  const i = parseSubmitDailyInput(input);
  const today = isoDate(now);
  if (Math.abs(daysBetween(i.date, today)) > DAILY_SUBMISSION_WINDOW_DAYS) {
    throw new HttpsError('failed-precondition', `date ${i.date} is outside the ${DAILY_SUBMISSION_WINDOW_DAYS}-day submission window (server date ${today})`);
  }
  const score = computeScore(i);
  const entriesPath = leaderboardEntriesPath(i.lang, i.date, i.variant);
  const entryPath = `${entriesPath}/${uid}`;

  await db.runTransaction(async (tx) => {
    const [daily, entry] = await Promise.all([tx.get(dailyDocPath(i.lang, i.date, i.variant)), tx.get(entryPath)]);
    if (!daily.exists) throw new HttpsError('not-found', `no published daily for ${i.lang} ${i.date} ${i.variant}`);
    if (readString(daily.data, 'puzzleId') !== i.puzzleId) {
      throw new HttpsError('invalid-argument', 'puzzleId does not match the published daily');
    }
    if (entry.exists) throw new HttpsError('already-exists', 'a result was already submitted for this daily');
    const letterCells = readNumber(daily.data, 'letterCells', 0);
    const minMs = DAILY_MIN_MS_PER_LETTER * letterCells;
    if (letterCells <= 0 || i.elapsedMs < minMs) {
      throw new HttpsError('failed-precondition', `elapsedMs ${i.elapsedMs} is below the plausibility floor of ${minMs} ms for ${letterCells} letter cells`);
    }
    const expectedHash = readString(daily.data, 'solutionHash');
    if (expectedHash === undefined) throw new HttpsError('failed-precondition', 'the leaderboard is not enabled for this daily (no solution hash)');
    if (expectedHash !== i.solutionHash) throw new HttpsError('failed-precondition', 'solution hash mismatch');
    tx.set(entryPath, {
      uid,
      puzzleId: i.puzzleId,
      score,
      elapsedMs: i.elapsedMs,
      lettersRevealed: i.lettersRevealed,
      wordsRevealed: i.wordsRevealed,
      checksUsed: i.checksUsed,
      mode: i.mode,
      submittedAt: now,
    });
  });

  const better = await db.countDocs(entriesPath, [{ field: 'score', op: '<', value: score }]);
  return { score, rank: better + 1 };
}
