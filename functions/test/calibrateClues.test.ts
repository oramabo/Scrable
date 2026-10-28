import { aggregateWordSolved, calibrateClues, median, WORD_SOLVED_COLLECTION } from '../src/handlers/calibrateClues';
import { FakeFirestore } from './fakeFirestore';
import { NOW } from './helpers';

describe('calibrateClues', () => {
  test('median handles odd, even and empty samples', () => {
    expect(median([])).toBe(0);
    expect(median([5])).toBe(5);
    expect(median([1, 2, 3])).toBe(2);
    expect(median([1, 2, 3, 10])).toBe(2.5);
  });

  test('aggregates events per clue into n, medianRelTime and hintRate', () => {
    const stats = aggregateWordSolved([
      { clueId: 'c1', relTime: 3, hinted: false, lang: 'he' },
      { clueId: 'c1', relTime: 1, hinted: true },
      { clueId: 'c1', relTime: 2, hinted: false },
      { clueId: 'c2', relTime: 4, hinted: false, lang: 'en' },
      { clueId: 'c2', relTime: 8, hinted: false },
    ]);
    expect(stats.get('c1')).toEqual({ n: 3, medianRelTime: 2, hintRate: 1 / 3, lang: 'he' });
    expect(stats.get('c2')).toEqual({ n: 2, medianRelTime: 6, hintRate: 0, lang: 'en' });
  });

  test('reads telemetry pages, skips malformed events and writes clueStats docs', async () => {
    const db = new FakeFirestore({
      [`${WORD_SOLVED_COLLECTION}/e1`]: { clueId: 'c1', relTime: 3, hinted: false, lang: 'he' },
      [`${WORD_SOLVED_COLLECTION}/e2`]: { clueId: 'c1', relTime: 1, hinted: true },
      [`${WORD_SOLVED_COLLECTION}/e3`]: { clueId: 'c1', relTime: 2, hinted: false },
      [`${WORD_SOLVED_COLLECTION}/e4`]: { clueId: 'c2', relTime: 4, hinted: false },
      [`${WORD_SOLVED_COLLECTION}/e5`]: { clueId: 'c2', relTime: -1, hinted: false }, // negative time: skipped
      [`${WORD_SOLVED_COLLECTION}/e6`]: { clueId: 42, relTime: 4, hinted: false }, // bad clueId: skipped
      [`${WORD_SOLVED_COLLECTION}/e7`]: { clueId: 'c2', relTime: 8, hinted: 'yes' }, // bad hinted: skipped
      'clueStats/c1': { editorialDifficulty: 0.4 },
    });
    const res = await calibrateClues(db, NOW, 2);
    expect(res).toEqual({ events: 4, skipped: 3, clues: 2 });
    expect(db.get('clueStats/c1')).toEqual({ editorialDifficulty: 0.4, n: 3, medianRelTime: 2, hintRate: 1 / 3, lang: 'he', updatedAt: NOW });
    expect(db.get('clueStats/c2')).toEqual({ n: 1, medianRelTime: 4, hintRate: 0, updatedAt: NOW });
  });
});
