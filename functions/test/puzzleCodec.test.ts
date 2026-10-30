import { canonicalJson, decodeLetterSymbols, letterCellCount, puzzleChecksum, solutionHash, verifyChecksum, wordCount } from '../src/lib/puzzleCodec';
import { loadFixtureText, loadPuzzle } from './helpers';

describe('puzzle codec port (must match packages/core PuzzleCodec)', () => {
  const daily = loadPuzzle('puzzle-daily-he.json');
  const pack = loadPuzzle('puzzle-pack-he.json');

  test('canonical JSON sorts keys, drops whitespace and writes integral numbers without a fraction', () => {
    expect(canonicalJson({ b: 1.0, a: [22.0, 0.5, 'x'], c: { z: null, y: true } })).toBe('{"a":[22,0.5,"x"],"b":1,"c":{"y":true,"z":null}}');
    expect(canonicalJson('עיר בנגב')).toBe('"עיר בנגב"');
  });

  test('decodes the xor1 solution to one symbol per letter cell', () => {
    const letters = decodeLetterSymbols(daily);
    expect(letters).toHaveLength(letterCellCount(daily.layout));
    expect(letters.every((s) => Number.isInteger(s) && s >= 0 && s < 64)).toBe(true);
  });

  test('recomputes the checksum the Dart generator wrote into the fixtures', () => {
    expect(puzzleChecksum(daily)).toBe(daily.meta.checksum);
    expect(puzzleChecksum(pack)).toBe(pack.meta.checksum);
    expect(verifyChecksum(daily).ok).toBe(true);
  });

  test('recomputes PuzzleCodec.solutionHash of the daily fixture', () => {
    expect(solutionHash(daily)).toBe(loadFixtureText('puzzle-daily-he.solutionHash.txt').trim());
  });

  test('a tampered clue text changes the checksum', () => {
    const tampered = JSON.parse(JSON.stringify(daily)) as typeof daily;
    (tampered['clueCells'] as Array<{ slots: Array<{ text: string }> }>)[0]!.slots[0]!.text = 'משהו אחר';
    expect(verifyChecksum(tampered).ok).toBe(false);
  });

  describe('compact format 2', () => {
    const dailyV2 = loadPuzzle('puzzle-daily-he-v2.json');
    const packV2 = loadPuzzle('puzzle-pack-he-v2.json');

    test('recomputes the checksum the Dart codec wrote', () => {
      expect(verifyChecksum(dailyV2).ok).toBe(true);
      expect(verifyChecksum(packV2).ok).toBe(true);
    });

    test('keeps the solution and its leaderboard hash', () => {
      expect(decodeLetterSymbols(dailyV2)).toEqual(decodeLetterSymbols(daily));
      expect(solutionHash(dailyV2)).toBe(loadFixtureText('puzzle-daily-he.solutionHash.txt').trim());
    });

    test('counts the same words as format 1', () => {
      expect(wordCount(dailyV2)).toBe(wordCount(daily));
      expect(wordCount(packV2)).toBe(wordCount(pack));
    });

    test('a tampered clue text changes the checksum', () => {
      const tampered = JSON.parse(JSON.stringify(dailyV2)) as typeof dailyV2;
      (tampered['clues'] as unknown[][])[0]![7] = 'משהו אחר';
      expect(verifyChecksum(tampered).ok).toBe(false);
    });
  });
});
