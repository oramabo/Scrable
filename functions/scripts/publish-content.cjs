#!/usr/bin/env node
/**
 * Publishes generated content to Firebase through the same code path as the
 * `publishPuzzle` / `rebuildManifests` callables, so Firestore documents,
 * Storage objects and CDN manifests are byte-for-byte what the functions
 * produce.
 *
 *   node scripts/publish-content.cjs --content ../content --lang he [--only daily|packs] [--from 2026-11-01] [--limit N] [--no-rebuild]
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS (service account with Firestore +
 * Storage access) and GCLOUD_PROJECT / FIREBASE_PROJECT; or the emulator env
 * (`firebase emulators:exec` sets FIRESTORE_EMULATOR_HOST and
 * FIREBASE_STORAGE_EMULATOR_HOST). STORAGE_BUCKET overrides the bucket name.
 * Run `npm run build` first.
 */
const fs = require('node:fs');
const path = require('node:path');

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

const { publishPuzzle } = require('../lib/handlers/publishPuzzle.js');
const { rebuildManifests } = require('../lib/handlers/rebuildManifests.js');
const { adminDb } = require('../lib/lib/firestoreAdmin.js');
const { adminStorage } = require('../lib/lib/storage.js');

function parseArgs(argv) {
  const out = { content: '../content', lang: 'he', only: 'all', from: undefined, limit: Infinity, rebuild: true };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--content') out.content = next();
    else if (a === '--lang') out.lang = next();
    else if (a === '--only') out.only = next();
    else if (a === '--from') out.from = next();
    else if (a === '--limit') out.limit = Number(next());
    else if (a === '--no-rebuild') out.rebuild = false;
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]);
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  if (out.lang !== 'he' && out.lang !== 'en') throw new Error('--lang must be he or en');
  if (!['all', 'daily', 'packs'].includes(out.only)) throw new Error('--only must be all, daily or packs');
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const contentRoot = path.resolve(args.content);
  const indexPath = path.join(contentRoot, args.lang, 'puzzles', 'manifests', 'publish-index.json');
  if (!fs.existsSync(indexPath)) throw new Error(`missing ${indexPath}; run \`chetz_gen manifest --lang ${args.lang}\` first`);
  const index = JSON.parse(fs.readFileSync(indexPath, 'utf8'));

  const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) throw new Error('set GCLOUD_PROJECT (or FIREBASE_PROJECT) to the Firebase project id');
  const bucketName = process.env.STORAGE_BUCKET || `${projectId}.appspot.com`;
  initializeApp({ projectId, storageBucket: bucketName });
  const deps = { db: adminDb(getFirestore()), storage: adminStorage(getStorage().bucket(bucketName), process.env.CDN_BASE_URL) };

  const packMeta = new Map();
  let entries = index.puzzles.filter((e) => e.lang === args.lang);
  if (args.only === 'daily') entries = entries.filter((e) => e.kind === 'daily');
  if (args.only === 'packs') entries = entries.filter((e) => e.kind === 'pack');
  if (args.from) entries = entries.filter((e) => e.kind !== 'daily' || e.date >= args.from);
  entries = entries.slice(0, args.limit);

  let published = 0;
  const failures = [];
  for (const entry of entries) {
    try {
      const puzzle = JSON.parse(fs.readFileSync(path.join(contentRoot, entry.file), 'utf8'));
      const input = { puzzle, lang: args.lang, solutionHash: entry.solutionHash };
      if (entry.kind === 'pack') {
        const packDir = path.dirname(path.join(contentRoot, entry.file));
        if (!packMeta.has(packDir)) {
          const pj = JSON.parse(fs.readFileSync(path.join(packDir, 'pack.json'), 'utf8'));
          packMeta.set(packDir, { index: pj.index, title: pj.title, free: Boolean(pj.free) });
        }
        input.pack = packMeta.get(packDir);
      }
      const result = await publishPuzzle(deps, input, Date.now(), 'publish-content-script');
      published++;
      if (published % 25 === 0 || published === entries.length) console.log(`${published}/${entries.length} published (last: ${result.id} → ${result.path})`);
    } catch (err) {
      failures.push({ id: entry.id, error: err instanceof Error ? err.message : String(err) });
      console.error(`FAILED ${entry.id}: ${failures[failures.length - 1].error}`);
    }
  }
  if (args.rebuild) {
    const r = await rebuildManifests(deps, { lang: args.lang }, Date.now());
    console.log(`manifests rebuilt: ${r.dailyEntries} dailies, ${r.packs} packs, ${r.files.length} files`);
  }
  console.log(`done: ${published} published, ${failures.length} failed`);
  process.exit(failures.length === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
