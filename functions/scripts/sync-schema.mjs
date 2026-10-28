#!/usr/bin/env node
// Copies the shared JSON Schemas from <repo>/schema into functions/schema so the
// deployed bundle (which only contains the functions/ directory) is self-contained.
import { copyFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, '..', '..', 'schema');
const target = resolve(here, '..', 'schema');

if (!existsSync(source)) {
  if (existsSync(target) && readdirSync(target).some((f) => f.endsWith('.schema.json'))) {
    console.log(`sync-schema: ${source} missing, keeping the existing copy in ${target}`);
    process.exit(0);
  }
  console.error(`sync-schema: ${source} not found and no copy in ${target}`);
  process.exit(1);
}
mkdirSync(target, { recursive: true });
const files = readdirSync(source).filter((f) => f.endsWith('.schema.json'));
for (const f of files) copyFileSync(join(source, f), join(target, f));
console.log(`sync-schema: copied ${files.length} schema file(s) to ${target}`);
