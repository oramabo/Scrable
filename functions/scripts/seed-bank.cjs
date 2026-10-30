#!/usr/bin/env node
/**
 * Loads the clue bank and the word bank into Firestore: one document per
 * record of content/<lang>/clues/clues.jsonl.gz (`clues/{id}`) and
 * content/<lang>/lexicon/words.jsonl.gz (`words/{id}`). Both collections are
 * admin-only in firestore.rules (a clue links to its answer). The documents
 * are the generator records unchanged, so the admin tools and the generator
 * read the same fields. Re-running overwrites them.
 *
 *   node scripts/seed-bank.cjs --content ../content --lang he [--only clues|words] [--limit N] [--dry-run]
 *
 * Credentials and project as for publish-content.cjs (GOOGLE_APPLICATION_CREDENTIALS,
 * GCLOUD_PROJECT), or the Firestore emulator (FIRESTORE_EMULATOR_HOST).
 */
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const SOURCES = {
  clues: (lang) => path.join(lang, 'clues', 'clues.jsonl.gz'),
  words: (lang) => path.join(lang, 'lexicon', 'words.jsonl.gz'),
};

function parseArgs(argv) {
  const out = { content: '../content', lang: 'he', only: 'all', limit: Infinity, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--content') out.content = argv[++i];
    else if (a === '--lang') out.lang = argv[++i];
    else if (a === '--only') out.only = argv[++i];
    else if (a === '--limit') out.limit = Number(argv[++i]);
    else if (a === '--dry-run') out.dryRun = true;
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]);
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  if (out.lang !== 'he' && out.lang !== 'en') throw new Error('--lang must be he or en');
  if (!['all', 'clues', 'words'].includes(out.only)) throw new Error('--only must be all, clues or words');
  return out;
}

function readJsonlGz(file) {
  return zlib
    .gunzipSync(fs.readFileSync(file))
    .toString('utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const contentRoot = path.resolve(args.content);
  const collections = args.only === 'all' ? ['clues', 'words'] : [args.only];

  let db;
  if (!args.dryRun) {
    const projectId = process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    if (!projectId) throw new Error('set GCLOUD_PROJECT (or FIREBASE_PROJECT) to the Firebase project id');
    initializeApp({ projectId });
    db = getFirestore();
  }

  for (const collection of collections) {
    const file = path.join(contentRoot, SOURCES[collection](args.lang));
    if (!fs.existsSync(file)) throw new Error(`missing ${file}`);
    const records = readJsonlGz(file).slice(0, args.limit);
    const bad = records.filter((r) => typeof r.id !== 'string' || r.id.length === 0 || r.id.includes('/') || r.lang !== args.lang);
    if (bad.length > 0) throw new Error(`${file}: ${bad.length} records without a usable id or with another lang (first: ${JSON.stringify(bad[0])})`);
    if (args.dryRun) {
      console.log(`${collection}: ${records.length} ${args.lang} records would be written`);
      continue;
    }
    const started = Date.now();
    let written = 0;
    const failures = [];
    const writer = db.bulkWriter();
    writer.onWriteResult(() => {
      written++;
      if (written % 20000 === 0) console.log(`${collection}: ${written}/${records.length} (${Math.round((Date.now() - started) / 1000)}s)`);
    });
    writer.onWriteError((err) => {
      if (err.failedAttempts < 5) return true;
      failures.push(`${err.documentRef.path}: ${err.message}`);
      return false;
    });
    for (const record of records) writer.set(db.collection(collection).doc(record.id), record);
    await writer.close();
    console.log(`${collection}: ${written} ${args.lang} documents written in ${Math.round((Date.now() - started) / 1000)}s${failures.length ? `, ${failures.length} failed (first: ${failures[0]})` : ''}`);
    if (failures.length) process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
