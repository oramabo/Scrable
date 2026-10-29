import { TROPHY_RULES } from '../src/economy';
import { applyTrophyDelta, expectedScore, lossDelta, trophyDelta, winDelta } from '../src/lib/trophies';

describe('trophy formula', () => {
  test('equal opponents: +30 / −15', () => {
    expect(expectedScore(500, 500)).toBeCloseTo(0.5);
    expect(winDelta(500, 500)).toBe(30);
    expect(lossDelta(500, 500)).toBe(-15);
    expect(trophyDelta('win', 0, 0)).toBe(30);
    expect(trophyDelta('loss', 0, 0)).toBe(-15);
    expect(trophyDelta('forfeit', 0, 0)).toBe(-15);
    expect(trophyDelta('draw', 0, 3000)).toBe(0);
  });

  test('beating a stronger player pays more, a weaker one less; losing mirrors it', () => {
    expect(winDelta(100, 300)).toBeGreaterThan(30);
    expect(winDelta(300, 100)).toBeLessThan(30);
    expect(winDelta(100, 300) + winDelta(300, 100)).toBe(60); // symmetric around the base
    expect(lossDelta(300, 100)).toBeLessThan(-15); // the favourite loses more
    expect(lossDelta(100, 300)).toBeGreaterThan(-15);
    // 400 trophies apart: E = 1/11 → win 30 + 40·(0.5 − 0.0909) ≈ 46, loss −(15 + 40·(0.909 − 0.5)) ≈ −31 → clamped −25
    expect(winDelta(0, 400)).toBe(46);
    expect(lossDelta(400, 0)).toBe(-25);
  });

  test('bounds: win in [10, 50], loss in [−25, −5] for any difference', () => {
    const extremes = [0, 1, 50, 200, 400, 800, 1600, 5000, 100_000];
    for (const a of extremes) {
      for (const b of extremes) {
        const w = winDelta(a, b);
        const l = lossDelta(a, b);
        expect(w).toBeGreaterThanOrEqual(TROPHY_RULES.winMin);
        expect(w).toBeLessThanOrEqual(TROPHY_RULES.winMax);
        expect(l).toBeLessThanOrEqual(-TROPHY_RULES.lossMin);
        expect(l).toBeGreaterThanOrEqual(-TROPHY_RULES.lossMax);
        expect(Number.isInteger(w) && Number.isInteger(l)).toBe(true);
      }
    }
    expect(winDelta(0, 100_000)).toBe(50);
    expect(winDelta(100_000, 0)).toBe(10);
    expect(lossDelta(100_000, 0)).toBe(-25);
    expect(lossDelta(0, 100_000)).toBe(-5);
  });

  test('trophies never drop below zero', () => {
    expect(applyTrophyDelta(10, -15)).toBe(0);
    expect(applyTrophyDelta(20, -15)).toBe(5);
    expect(applyTrophyDelta(0, 30)).toBe(30);
  });
});
