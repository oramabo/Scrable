/**
 * Shared ajv (draft 2020-12) instance loaded with the JSON Schemas from
 * schema/ at the repository root. `npm run build` copies them into
 * functions/schema so the deployed bundle is self-contained; when that copy is
 * missing (plain `jest` run) the repository copy is used.
 */
import { existsSync, readFileSync } from 'node:fs';
import * as path from 'node:path';

import Ajv2020, { type ErrorObject, type ValidateFunction } from 'ajv/dist/2020';
import addFormats from 'ajv-formats';

export type SchemaName = 'puzzle' | 'progress' | 'ledger-entry' | 'daily-manifest' | 'packs-manifest' | 'manifest';

const SCHEMA_FILES: Record<SchemaName, string> = {
  puzzle: 'puzzle.schema.json',
  progress: 'progress.schema.json',
  'ledger-entry': 'ledger-entry.schema.json',
  'daily-manifest': 'daily-manifest.schema.json',
  'packs-manifest': 'packs-manifest.schema.json',
  manifest: 'manifest.schema.json',
};

const CANDIDATE_DIRS = [
  path.resolve(__dirname, '..', '..', 'schema'), // functions/schema (build-time copy) from lib/lib or src/lib
  path.resolve(__dirname, '..', '..', '..', 'schema'), // <repo>/schema
];

export function schemaDir(): string {
  const override = process.env['CHETZ_SCHEMA_DIR'];
  if (override && existsSync(path.join(override, SCHEMA_FILES.puzzle))) return override;
  for (const dir of CANDIDATE_DIRS) {
    if (existsSync(path.join(dir, SCHEMA_FILES.puzzle))) return dir;
  }
  throw new Error(`JSON schemas not found; looked in ${CANDIDATE_DIRS.join(', ')}. Run \`npm run sync-schema\`.`);
}

let ajvInstance: Ajv2020 | undefined;
const compiled = new Map<SchemaName, ValidateFunction>();

function ajv(): Ajv2020 {
  if (ajvInstance) return ajvInstance;
  const instance = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true });
  addFormats(instance);
  const dir = schemaDir();
  for (const file of Object.values(SCHEMA_FILES)) {
    const schema = JSON.parse(readFileSync(path.join(dir, file), 'utf8')) as Record<string, unknown>;
    instance.addSchema(schema);
  }
  ajvInstance = instance;
  return instance;
}

export function loadSchema(name: SchemaName): Record<string, unknown> {
  return JSON.parse(readFileSync(path.join(schemaDir(), SCHEMA_FILES[name]), 'utf8')) as Record<string, unknown>;
}

export function validator(name: SchemaName): ValidateFunction {
  const existing = compiled.get(name);
  if (existing) return existing;
  const instance = ajv();
  const schema = loadSchema(name);
  const id = schema['$id'];
  if (typeof id !== 'string') throw new Error(`schema ${name} has no $id`);
  const fn = instance.getSchema(id);
  if (!fn) throw new Error(`schema ${id} not registered`);
  compiled.set(name, fn);
  return fn;
}

export interface ValidationResult {
  ok: boolean;
  errors: string[];
}

export function formatErrors(errors: ErrorObject[] | null | undefined, max = 20): string[] {
  if (!errors) return [];
  return errors.slice(0, max).map((e) => {
    const where = e.instancePath.length > 0 ? e.instancePath : '/';
    const params = Object.keys(e.params).length > 0 ? ` ${JSON.stringify(e.params)}` : '';
    return `${where} ${e.message ?? 'invalid'}${params}`;
  });
}

/** Validates `data` against a named schema, returning readable error strings. */
export function validate(name: SchemaName, data: unknown): ValidationResult {
  const fn = validator(name);
  const ok = fn(data) === true;
  return { ok, errors: ok ? [] : formatErrors(fn.errors) };
}
