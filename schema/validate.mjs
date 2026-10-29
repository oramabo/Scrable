#!/usr/bin/env node
// Validates every fixture in schema/fixtures against its schema and compiles
// every schema (draft 2020-12). Used by CI (ci-functions.yml) and locally:
//   npm ci --prefix schema && node schema/validate.mjs
// With `--content <dir>` it additionally validates every generated puzzle and
// manifest under <dir>/*/puzzles (content CI).
// Falls back to functions/node_modules when schema/ has no node_modules.
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

function loadAjv() {
  const candidates = [join(here, 'package.json'), join(here, '..', 'functions', 'package.json')];
  const errors = [];
  for (const c of candidates) {
    try {
      const req = createRequire(c);
      const ajvMod = req('ajv/dist/2020');
      const formatsMod = req('ajv-formats');
      return { Ajv2020: ajvMod.default ?? ajvMod, addFormats: formatsMod.default ?? formatsMod };
    } catch (e) {
      errors.push(`${dirname(c)}: ${e.message.split('\n')[0]}`);
    }
  }
  throw new Error(`ajv + ajv-formats not found. Run \`npm ci\` in schema/ or functions/.\n${errors.join('\n')}`);
}

const { Ajv2020, addFormats } = loadAjv();
const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true });
addFormats(ajv);

const schemaFiles = readdirSync(here).filter((f) => f.endsWith('.schema.json')).sort();
const schemas = {};
for (const f of schemaFiles) {
  const schema = JSON.parse(readFileSync(join(here, f), 'utf8'));
  schemas[f] = schema;
  ajv.addSchema(schema);
}
let failures = 0;
for (const f of schemaFiles) {
  try {
    ajv.compile(schemas[f]);
    console.log(`schema ok    ${f}`);
  } catch (e) {
    failures++;
    console.error(`schema FAIL  ${f}: ${e.message}`);
  }
}

// fixture file name prefix -> schema file
const mapping = [
  ['puzzle-', 'puzzle.schema.json'],
  ['progress-', 'progress.schema.json'],
  ['ledger-entry-', 'ledger-entry.schema.json'],
  ['daily-manifest-', 'daily-manifest.schema.json'],
  ['packs-manifest-', 'packs-manifest.schema.json'],
  ['publish-index-', 'publish-index.schema.json'],
  ['match-', 'match.schema.json'],
  ['coop-room-', 'coop-room.schema.json'],
];

/** Extra structural checks the JSON Schema cannot express. */
function puzzleSemanticErrors(p) {
  const errs = [];
  if (p.layout.length !== p.grid.rows) errs.push(`layout has ${p.layout.length} rows, grid.rows=${p.grid.rows}`);
  for (const [i, row] of p.layout.entries()) {
    if (row.length !== p.grid.cols) errs.push(`layout row ${i} has ${row.length} cells, grid.cols=${p.grid.cols}`);
  }
  const letterCells = p.layout.join('').split('').filter((ch) => ch === 'L').length;
  if (p.solution.enc === 'plain' && p.solution.data.length !== letterCells) {
    errs.push(`plain solution has ${p.solution.data.length} symbols for ${letterCells} letter cells`);
  }
  if (p.solution.enc === 'xor1') {
    const bytes = Buffer.from(p.solution.data, 'base64').length;
    if (bytes !== letterCells) errs.push(`xor1 solution decodes to ${bytes} bytes for ${letterCells} letter cells`);
  }
  if (p.kind === 'daily' && !p.daily) errs.push('kind=daily without daily{}');
  if (p.kind === 'pack' && !p.pack) errs.push('kind=pack without pack{}');
  const wordIds = new Set(p.words.map((w) => w.id));
  if (wordIds.size !== p.words.length) errs.push('duplicate word ids');
  const slotWordIds = new Set();
  for (const cell of p.clueCells) {
    if (p.layout[cell.r]?.[cell.c] !== 'C') errs.push(`clue cell (${cell.r},${cell.c}) is not a C in layout`);
    for (const s of cell.slots) {
      if (!wordIds.has(s.wordId)) errs.push(`slot in (${cell.r},${cell.c}) references unknown word ${s.wordId}`);
      if (slotWordIds.has(s.wordId)) errs.push(`word ${s.wordId} has two clue slots`);
      slotWordIds.add(s.wordId);
    }
  }
  for (const w of p.words) {
    if (!slotWordIds.has(w.id)) errs.push(`word ${w.id} has no clue slot`);
    if (p.layout[w.clueCell.r]?.[w.clueCell.c] !== 'C') errs.push(`word ${w.id} clue cell is not a C`);
    for (let k = 0; k < w.len; k++) {
      const r = w.dir === 'A' ? w.start.r : w.start.r + k;
      const c = w.dir === 'A' ? w.start.c + k : w.start.c;
      if (p.layout[r]?.[c] !== 'L') errs.push(`word ${w.id} covers non-letter cell (${r},${c})`);
    }
  }
  return errs;
}

const fixturesDir = join(here, 'fixtures');
const fixtures = existsSync(fixturesDir) ? readdirSync(fixturesDir).filter((f) => f.endsWith('.json')).sort() : [];
if (fixtures.length === 0) {
  failures++;
  console.error('no fixtures found in schema/fixtures');
}
for (const f of fixtures) {
  const entry = mapping.find(([prefix]) => f.startsWith(prefix));
  if (!entry) {
    failures++;
    console.error(`fixture FAIL ${f}: no schema mapping for this file name prefix`);
    continue;
  }
  const [, schemaFile] = entry;
  const validate = ajv.getSchema(schemas[schemaFile].$id);
  const data = JSON.parse(readFileSync(join(fixturesDir, f), 'utf8'));
  const ok = validate(data);
  const semantic = schemaFile === 'puzzle.schema.json' && ok ? puzzleSemanticErrors(data) : [];
  if (ok && semantic.length === 0) {
    console.log(`fixture ok   ${f}  (${schemaFile})`);
  } else {
    failures++;
    console.error(`fixture FAIL ${f}  (${schemaFile})`);
    for (const e of validate.errors ?? []) console.error(`   ${e.instancePath || '/'} ${e.message} ${JSON.stringify(e.params)}`);
    for (const e of semantic) console.error(`   semantic: ${e}`);
  }
}
// --content <dir>: every puzzle + manifest the content pipeline generated.
const contentArg = process.argv.indexOf('--content');
let contentFiles = 0;
if (contentArg !== -1) {
  const root = process.argv[contentArg + 1];
  if (!root || !existsSync(root)) {
    failures++;
    console.error(`--content: directory not found: ${root}`);
  } else {
    const walk = (dir, out) => {
      for (const name of readdirSync(dir)) {
        const full = join(dir, name);
        if (statSync(full).isDirectory()) walk(full, out);
        else if (name.endsWith('.json')) out.push(full);
      }
      return out;
    };
    const byKind = { puzzle: 0, 'daily-manifest': 0, 'packs-manifest': 0, 'publish-index': 0 };
    for (const file of walk(root, []).filter((f) => f.includes('/puzzles/')).sort()) {
      const base = file.slice(file.lastIndexOf('/') + 1);
      let schemaFile;
      if (base === 'pack.json') continue; // pipeline-internal pack metadata
      else if (base === 'daily.json') schemaFile = 'daily-manifest.schema.json';
      else if (base === 'packs.json') schemaFile = 'packs-manifest.schema.json';
      else if (base === 'publish-index.json') schemaFile = 'publish-index.schema.json';
      else schemaFile = 'puzzle.schema.json';
      const validate = ajv.getSchema(schemas[schemaFile].$id);
      const data = JSON.parse(readFileSync(file, 'utf8'));
      const ok = validate(data);
      const semantic = schemaFile === 'puzzle.schema.json' && ok ? puzzleSemanticErrors(data) : [];
      contentFiles++;
      if (ok && semantic.length === 0) {
        byKind[schemaFile.replace('.schema.json', '')]++;
        continue;
      }
      failures++;
      console.error(`content FAIL ${file}  (${schemaFile})`);
      for (const e of (validate.errors ?? []).slice(0, 10)) console.error(`   ${e.instancePath || '/'} ${e.message} ${JSON.stringify(e.params)}`);
      for (const e of semantic.slice(0, 10)) console.error(`   semantic: ${e}`);
    }
    console.log(`content: ${contentFiles} files checked under ${root} (${JSON.stringify(byKind)})`);
  }
}

if (failures > 0) {
  console.error(`\n${failures} failure(s)`);
  process.exit(1);
}
console.log(`\nall ${schemaFiles.length} schemas, ${fixtures.length} fixtures${contentFiles ? ` and ${contentFiles} content files` : ''} valid`);
