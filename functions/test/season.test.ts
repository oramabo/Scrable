import { SEASON_EPOCH_DATE, seasonBounds, seasonBoundsFor, seasonIdAt, seasonIdFor, seasonNumberFor } from '../src/lib/season';

describe('season calendar (42-day seasons from 2026-11-02)', () => {
  test('season 1 starts on the epoch Monday and lasts 42 days', () => {
    expect(seasonIdFor(SEASON_EPOCH_DATE)).toBe('2026-S1');
    expect(seasonIdFor('2026-12-13')).toBe('2026-S1'); // last day of season 1
    expect(seasonIdFor('2026-12-14')).toBe('2026-S2');
    expect(seasonBounds('2026-S1')).toEqual({
      id: '2026-S1',
      n: 1,
      start: '2026-11-02',
      end: '2026-12-13',
      startMs: Date.UTC(2026, 10, 2),
      endMs: Date.UTC(2026, 11, 14),
    });
    expect(new Date(Date.UTC(2026, 10, 2)).getUTCDay()).toBe(1); // Monday
  });

  test('the year prefix is the season start year; the number never resets', () => {
    expect(seasonIdFor('2027-01-24')).toBe('2026-S2'); // season 2 started 2026-12-14
    expect(seasonIdFor('2027-01-25')).toBe('2027-S3');
    expect(seasonBounds(3)?.start).toBe('2027-01-25');
    expect(seasonBounds('2027-S3')?.end).toBe('2027-03-07');
    expect(seasonBoundsFor('2027-03-08')?.id).toBe('2027-S4');
    expect(seasonNumberFor('2028-01-01')).toBe(11);
  });

  test('dates before season 1 and malformed input have no season', () => {
    expect(seasonIdFor('2026-11-01')).toBeUndefined();
    expect(seasonIdFor('2026-10-30')).toBeUndefined();
    expect(seasonIdFor('nope')).toBeUndefined();
    expect(seasonBounds('2027-S2')).toBeUndefined(); // wrong year prefix for season 2
    expect(seasonBounds('2026-S0')).toBeUndefined();
    expect(seasonBounds(0)).toBeUndefined();
    expect(seasonIdAt(Date.UTC(2026, 10, 1, 23, 59, 59))).toBeUndefined();
    expect(seasonIdAt(Date.UTC(2026, 10, 2, 0, 0, 0))).toBe('2026-S1');
  });
});
