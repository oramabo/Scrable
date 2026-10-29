import { canonicalJson, decodeLetterSymbols, letterCellCount, puzzleChecksum, solutionHash, verifyChecksum } from '../src/lib/puzzleCodec';
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
});
