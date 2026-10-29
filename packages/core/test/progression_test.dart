import 'package:chetz_core/meta.dart';
import 'package:test/test.dart';

void main() {
  test('xp curve is monotonic and level progress is bounded', () {
    expect(XpCurve.levelForXp(0), 1);
    expect(XpCurve.levelForXp(99), 1);
    expect(XpCurve.levelForXp(100), 2);
    expect(XpCurve.xpForLevel(10), 2700);
    expect(XpCurve.levelForXp(2700), 10);
    expect(XpCurve.levelProgress(150), inInclusiveRange(0.0, 1.0));
    expect(XpCurve.puzzleXp(1), 20);
    expect(XpCurve.puzzleXp(5, perfect: true, underPar: true, daily: true), 20 + 60 + 35);
    expect(XpCurve.rankIndex(1), 0);
    expect(XpCurve.rankIndex(60), 5);
  });

  test('seasons are six weeks from 2026-11-02', () {
    expect(SeasonPass.seasonNumber('2026-10-30'), 0);
    expect(SeasonPass.seasonNumber('2026-11-02'), 1);
    expect(SeasonPass.seasonNumber('2026-12-13'), 1);
    expect(SeasonPass.seasonNumber('2026-12-14'), 2);
    expect(SeasonPass.seasonId('2026-12-14'), '2026-S2');
    expect(SeasonPass.seasonId('2027-01-25'), '2027-S3');
    expect(SeasonPass.daysLeft('2026-11-02'), 41);
    expect(SeasonPass.daysLeft('2026-12-13'), 0);
    expect(SeasonPass.tiers.length, 30);
    expect(SeasonPass.tierFor(250), 2);
    expect(SeasonPass.tierFor(99999), 30);
    expect(SeasonPass.tiers[9].badge, 'season_tier_10');
    expect(SeasonPass.totalCoinsThroughTier(30), greaterThan(2000));
  });

  test('trophy deltas stay inside their bounds and favour upsets', () {
    expect(Trophies.winDelta(100, 100), 30);
    expect(Trophies.winDelta(100, 900), 50);
    expect(Trophies.winDelta(900, 100), 10);
    expect(Trophies.lossDelta(100, 100), -15);
    expect(Trophies.lossDelta(900, 100), -25);
    expect(Trophies.lossDelta(100, 900), -5);
    expect(Trophies.applyDelta(3, -15), 0);
    expect(Trophies.leagueIndex(0), 0);
    expect(Trophies.leagueIndex(2600), 6);
  });
}
