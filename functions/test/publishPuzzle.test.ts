import { publishPuzzle } from '../src/handlers/publishPuzzle';
import { rebuildManifests } from '../src/handlers/rebuildManifests';
import { dailyDocPath } from '../src/handlers/submitDaily';
import { letterCellCount, puzzleChecksum, type PuzzleLike, wordCount } from '../src/lib/puzzleCodec';
import { CACHE_IMMUTABLE, CACHE_SHORT } from '../src/lib/storage';
import { validate } from '../src/lib/validate';
import { FakeFirestore } from './fakeFirestore';
import { FakeStorage } from './fakes';
import { loadFixtureText, loadPuzzle, NOW } from './helpers';

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

/** Modifies a puzzle and re-signs it so only the intended check fails. */
function resigned(p: PuzzleLike, mutate: (q: PuzzleLike) => void): PuzzleLike {
  const q = clone(p);
  mutate(q);
  q.meta = { ...q.meta, checksum: puzzleChecksum(q) };
  return q;
}

describe('publishPuzzle', () => {
  const daily = loadPuzzle('puzzle-daily-he.json');
  const pack = loadPuzzle('puzzle-pack-he.json');

  test('publishes a daily: immutable file, dailies doc with letterCells + solutionHash, manifest source entry', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const res = await publishPuzzle({ db, storage }, { puzzle: daily, lang: 'he' }, NOW, 'admin1');
    expect(res).toMatchObject({ id: daily.id, kind: 'daily', path: 'puzzles/he/daily/easy/2026-11-01.v1.json', url: 'https://cdn.test/puzzles/he/daily/easy/2026-11-01.v1.json', checksum: daily.meta.checksum });
    expect(storage.objects.get(res.path)).toEqual({ data: daily, cacheControl: CACHE_IMMUTABLE });
    const dailyDoc = db.get(dailyDocPath('he', '2026-11-01', 'easy'));
    expect(dailyDoc).toMatchObject({ puzzleId: daily.id, letterCells: letterCellCount(daily.layout), solutionHash: loadFixtureText('puzzle-daily-he.solutionHash.txt').trim(), publishedBy: 'admin1', version: 1 });
    expect(db.get('manifests/he_daily')).toMatchObject({ lang: 'he', entries: { '2026-11-01_easy': { id: daily.id, variant: 'easy', checksum: daily.meta.checksum, path: res.path, url: res.url } } });
  });

  test('publishes a compact format-2 daily with the same solution hash', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const dailyV2 = loadPuzzle('puzzle-daily-he-v2.json');
    const res = await publishPuzzle({ db, storage }, { puzzle: dailyV2, lang: 'he' }, NOW, 'admin1');
    expect(res).toMatchObject({ id: daily.id, solutionHash: loadFixtureText('puzzle-daily-he.solutionHash.txt').trim(), letterCells: letterCellCount(daily.layout) });
    expect(storage.objects.get(res.path)).toEqual({ data: dailyV2, cacheControl: CACHE_IMMUTABLE });
    const badEntry = clone(dailyV2);
    (badEntry['clues'] as unknown[][])[0]![3] = 'X';
    await expect(publishPuzzle({ db, storage }, { puzzle: badEntry, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/schema/) });
  });

  test('accepts a matching publisher solutionHash and rejects a wrong one', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const hash = loadFixtureText('puzzle-daily-he.solutionHash.txt').trim();
    await expect(publishPuzzle({ db, storage }, { puzzle: daily, lang: 'he', solutionHash: hash }, NOW, 'a')).resolves.toMatchObject({ solutionHash: hash });
    await expect(publishPuzzle({ db, storage }, { puzzle: daily, lang: 'he', solutionHash: 'f'.repeat(64) }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/solutionHash/) });
  });

  test('rejects puzzles that do not match the JSON schema', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const noGrid = clone(daily) as Record<string, unknown>;
    delete noGrid['grid'];
    await expect(publishPuzzle({ db, storage }, { puzzle: noGrid, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/schema.*grid/) });
    await expect(publishPuzzle({ db, storage }, { puzzle: { ...clone(daily), kind: 'bogus' }, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/schema/) });
    await expect(publishPuzzle({ db, storage }, { puzzle: { ...clone(daily), answers: ['leak'] }, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/additional/) });
    const badArrow = clone(daily);
    (badArrow['words'] as Array<{ arrow: string }>)[0]!.arrow = 'X';
    await expect(publishPuzzle({ db, storage }, { puzzle: badArrow, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument' });
    expect(storage.objects.size).toBe(0);
    expect(db.writeCount).toBe(0);
  });

  test('rejects a missing, tampered or stale checksum and a lang mismatch', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const noChecksum = clone(daily);
    delete noChecksum.meta.checksum;
    await expect(publishPuzzle({ db, storage }, { puzzle: noChecksum, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ message: expect.stringMatching(/checksum is required/) });
    const tampered = clone(daily);
    tampered.meta.checksum = `sha256:${'0'.repeat(64)}`;
    await expect(publishPuzzle({ db, storage }, { puzzle: tampered, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ message: expect.stringMatching(/does not match the recomputed/) });
    const edited = clone(daily);
    (edited['clueCells'] as Array<{ slots: Array<{ text: string }> }>)[0]!.slots[0]!.text = 'רמז אחר';
    await expect(publishPuzzle({ db, storage }, { puzzle: edited, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ message: expect.stringMatching(/does not match the recomputed/) });
    await expect(publishPuzzle({ db, storage }, { puzzle: daily, lang: 'en' }, NOW, 'a')).rejects.toMatchObject({ message: expect.stringMatching(/lang/) });
    expect(storage.objects.size).toBe(0);
  });

  test('rejects tutorial/practice puzzles (they ship inside the app) and malformed input', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const tutorial = resigned(daily, (q) => {
      q.kind = 'tutorial';
      delete q.daily;
    });
    await expect(publishPuzzle({ db, storage }, { puzzle: tutorial, lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument', message: expect.stringMatching(/only daily and pack/) });
    await expect(publishPuzzle({ db, storage }, { lang: 'he' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(publishPuzzle({ db, storage }, { puzzle: daily, lang: 'fr' }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  test('publishes pack puzzles and accumulates them in the packs manifest source', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const first = await publishPuzzle({ db, storage }, { puzzle: pack, lang: 'he' }, NOW, 'a');
    expect(first.path).toBe('puzzles/he/packs/he-l1-001/01.v1.json');
    const second = resigned(pack, (q) => {
      q.id = 'he-l1-001-02';
      q.pack = { id: 'he-l1-001', index: 2 };
    });
    await publishPuzzle({ db, storage }, { puzzle: second, lang: 'he', pack: { title: { he: 'רמה 1 · חבילה 1', en: 'Level 1 · Pack 1' } } }, NOW + 1000, 'a');
    await expect(publishPuzzle({ db, storage }, { puzzle: second, lang: 'he', pack: { title: 7 } }, NOW, 'a')).rejects.toMatchObject({ code: 'invalid-argument' });
    const doc = db.get('manifests/he_packs');
    expect(doc).toMatchObject({
      lang: 'he',
      packs: {
        'he-l1-001': {
          id: 'he-l1-001',
          level: 1,
          index: 1,
          free: true,
          title: { he: 'רמה 1 · חבילה 1', en: 'Level 1 · Pack 1' },
          puzzles: { '001': { index: 1, id: pack.id, checksum: pack.meta.checksum, difficulty: pack.difficulty.score, words: wordCount(pack) }, '002': { index: 2, id: 'he-l1-001-02' } },
        },
      },
    });
  });
});

describe('rebuildManifests', () => {
  test('produces schema-valid daily and packs manifests plus pack index files', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    const daily = loadPuzzle('puzzle-daily-he.json');
    const pack = loadPuzzle('puzzle-pack-he.json');
    await publishPuzzle({ db, storage }, { puzzle: daily, lang: 'he' }, NOW, 'a');
    await publishPuzzle({ db, storage }, { puzzle: pack, lang: 'he' }, NOW, 'a');
    const res = await rebuildManifests({ db, storage }, { lang: 'he' }, NOW);
    expect(res).toEqual({ lang: 'he', dailyEntries: 1, packs: 1, files: ['manifests/he/daily.json', 'puzzles/he/packs/he-l1-001/pack.v1.json', 'manifests/he/packs.json'] });

    const dailyManifest = storage.json('manifests/he/daily.json') as { entries: unknown[] };
    expect(validate('daily-manifest', dailyManifest)).toEqual({ ok: true, errors: [] });
    // urls are CDN-relative, exactly like `chetz_gen manifest`; the app prefixes its cdnBaseUrl
    expect(dailyManifest.entries).toEqual([{ date: '2026-11-01', variant: 'easy', id: daily.id, url: 'puzzles/he/daily/easy/2026-11-01.v1.json', checksum: daily.meta.checksum, version: 1 }]);
    expect(storage.objects.get('manifests/he/daily.json')?.cacheControl).toBe(CACHE_SHORT);

    const packsManifest = storage.json('manifests/he/packs.json') as { packs: Array<Record<string, unknown>> };
    expect(validate('packs-manifest', packsManifest)).toEqual({ ok: true, errors: [] });
    const expectedPuzzles = [{ id: pack.id, index: 1, url: 'puzzles/he/packs/he-l1-001/01.v1.json', checksum: pack.meta.checksum, version: 1, difficulty: pack.difficulty.score, words: wordCount(pack) }];
    expect(packsManifest.packs[0]).toMatchObject({ id: 'he-l1-001', lang: 'he', level: 1, index: 1, title: pack.title, puzzleCount: 1, free: true, url: 'puzzles/he/packs/he-l1-001/pack.v1.json', puzzles: expectedPuzzles });
    const packFile = storage.json('puzzles/he/packs/he-l1-001/pack.v1.json') as { puzzles: Array<{ id: string }>; checksum: string; puzzleCount: number };
    expect(packFile).toMatchObject({ id: 'he-l1-001', lang: 'he', puzzleCount: 1, puzzles: expectedPuzzles });
    expect(packFile.checksum).toBe(packsManifest.packs[0]!['checksum']);

    // The pack checksum depends on content only, not on when the manifest was built.
    await rebuildManifests({ db, storage }, { lang: 'he' }, NOW + 86_400_000);
    expect((storage.json('manifests/he/packs.json') as { packs: Array<Record<string, unknown>> }).packs[0]!['checksum']).toBe(packFile.checksum);
  });

  test('keeps only the last 365 and next 3 days of dailies and copes with no data', async () => {
    const db = new FakeFirestore();
    const storage = new FakeStorage();
    await publishPuzzle({ db, storage }, { puzzle: loadPuzzle('puzzle-daily-he.json'), lang: 'he' }, NOW, 'a');
    const tooEarly = await rebuildManifests({ db, storage }, { lang: 'he' }, Date.UTC(2026, 9, 20));
    expect(tooEarly.dailyEntries).toBe(0);
    const laterInYear = await rebuildManifests({ db, storage }, { lang: 'he' }, Date.UTC(2027, 9, 1));
    expect(laterInYear.dailyEntries).toBe(1);
    const tooLate = await rebuildManifests({ db, storage }, { lang: 'he' }, Date.UTC(2027, 11, 1));
    expect(tooLate.dailyEntries).toBe(0);
    const empty = await rebuildManifests({ db, storage }, { lang: 'en' }, NOW);
    expect(empty).toMatchObject({ dailyEntries: 0, packs: 0 });
    expect(validate('packs-manifest', storage.json('manifests/en/packs.json'))).toEqual({ ok: true, errors: [] });
    await expect(rebuildManifests({ db, storage }, { lang: 'xx' }, NOW)).rejects.toMatchObject({ code: 'invalid-argument' });
  });
});
