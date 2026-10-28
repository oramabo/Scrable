import { DAILY_MIN_MS_PER_LETTER } from '../src/economy';
import { computeScore, dailyDocPath, leaderboardEntriesPath, submitDaily } from '../src/handlers/submitDaily';
import { FakeFirestore } from './fakeFirestore';
import { NOW } from './helpers';

const LETTER_CELLS = 50;
const HASH = 'a'.repeat(64);
const DATE = '2026-10-30';

function seededDb(): FakeFirestore {
  return new FakeFirestore({
    [dailyDocPath('he', DATE, 'hard')]: { puzzleId: 'he-d-2026-10-30-hard', letterCells: LETTER_CELLS, solutionHash: HASH, publishedAt: NOW - 3_600_000 },
  });
}

function input(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    puzzleId: 'he-d-2026-10-30-hard',
    lang: 'he',
    date: DATE,
    variant: 'hard',
    elapsedMs: 400_000,
    lettersRevealed: 0,
    wordsRevealed: 0,
    checksUsed: 0,
    mode: 'newspaper',
    solutionHash: HASH,
    ...overrides,
  };
}

describe('computeScore', () => {
  test('applies the documented formula', () => {
    expect(computeScore({ elapsedMs: 100_000, lettersRevealed: 1, wordsRevealed: 1, checksUsed: 1, mode: 'normal' })).toBe(100_000 + 20_000 + 60_000 + 15_000 + 5_000);
    expect(computeScore({ elapsedMs: 100_000, lettersRevealed: 0, wordsRevealed: 0, checksUsed: 0, mode: 'relaxed' })).toBe(115_000);
    expect(computeScore({ elapsedMs: 100_000, lettersRevealed: 2, wordsRevealed: 0, checksUsed: 0, mode: 'newspaper' })).toBe(140_000);
  });
});

describe('submitDaily', () => {
  test('rejects implausibly fast solves', async () => {
    const db = seededDb();
    const floor = DAILY_MIN_MS_PER_LETTER * LETTER_CELLS;
    await expect(submitDaily(db, 'u1', input({ elapsedMs: floor - 1 }), NOW)).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(db.list(leaderboardEntriesPath('he', DATE, 'hard'))).toEqual([]);
    await expect(submitDaily(db, 'u1', input({ elapsedMs: floor }), NOW)).resolves.toMatchObject({ rank: 1 });
  });

  test('rejects a wrong solution hash', async () => {
    const db = seededDb();
    await expect(submitDaily(db, 'u1', input({ solutionHash: 'b'.repeat(64) }), NOW)).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  test('rejects duplicates, unknown dailies and puzzle id mismatches', async () => {
    const db = seededDb();
    await submitDaily(db, 'u1', input(), NOW);
    await expect(submitDaily(db, 'u1', input({ elapsedMs: 500_000 }), NOW)).rejects.toMatchObject({ code: 'already-exists' });
    await expect(submitDaily(db, 'u2', input({ variant: 'easy' }), NOW)).rejects.toMatchObject({ code: 'not-found' });
    await expect(submitDaily(db, 'u2', input({ puzzleId: 'he-d-other' }), NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('rejects dates outside the two-day window and malformed input', async () => {
    const db = seededDb();
    await expect(submitDaily(db, 'u1', input(), NOW + 3 * 86_400_000)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(submitDaily(db, 'u1', input(), NOW + 2 * 86_400_000)).resolves.toBeDefined();
    await expect(submitDaily(db, 'u2', input({ date: '2026-13-01' }), NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(submitDaily(db, 'u2', input({ mode: 'turbo' }), NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(submitDaily(db, 'u2', input({ elapsedMs: 12.5 }), NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(submitDaily(db, 'u2', input({ solutionHash: 'xyz' }), NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(submitDaily(db, 'u2', 'nope', NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('stores the entry with the computed score and ranks by lower score', async () => {
    const db = seededDb();
    const slow = await submitDaily(db, 'slow', input({ elapsedMs: 600_000, mode: 'relaxed' }), NOW);
    expect(slow).toEqual({ score: 690_000, rank: 1 });
    const fast = await submitDaily(db, 'fast', input({ elapsedMs: 300_000 }), NOW);
    expect(fast).toEqual({ score: 300_000, rank: 1 });
    const mid = await submitDaily(db, 'mid', input({ elapsedMs: 300_000, lettersRevealed: 1 }), NOW);
    expect(mid).toEqual({ score: 320_000, rank: 2 });
    expect(db.get(`${leaderboardEntriesPath('he', DATE, 'hard')}/mid`)).toMatchObject({ uid: 'mid', score: 320_000, lettersRevealed: 1, mode: 'newspaper', submittedAt: NOW });
  });
});
