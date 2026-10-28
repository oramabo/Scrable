import { readFileSync } from 'node:fs';
import * as path from 'node:path';

import type { PuzzleLike } from '../src/lib/puzzleCodec';

/** 2026-10-30T12:00:00Z */
export const NOW = Date.UTC(2026, 9, 30, 12, 0, 0);

const FIXTURES = path.resolve(__dirname, '..', '..', 'schema', 'fixtures');

export function loadFixtureText(name: string): string {
  return readFileSync(path.join(FIXTURES, name), 'utf8');
}

export function loadFixture<T = unknown>(name: string): T {
  return JSON.parse(loadFixtureText(name)) as T;
}

export function loadPuzzle(name: string): PuzzleLike {
  return loadFixture<PuzzleLike>(name);
}

/** Deterministic, valid UUID v7 for test entries (`seq` keeps them unique and time-ordered). */
export function uuid7(seq: number, timeMs: number = NOW): string {
  const t = (timeMs + seq).toString(16).padStart(12, '0').slice(-12);
  const s = seq.toString(16).padStart(3, '0').slice(-3);
  const tail = seq.toString(16).padStart(12, '0').slice(-12);
  return `${t.slice(0, 8)}-${t.slice(8, 12)}-7${s}-8${s}-${tail}`;
}

export interface EntryOverrides {
  id?: string;
  refId?: string | null;
  createdAt?: number;
  deviceId?: string;
  balanceAfter?: number;
  lang?: string;
}

let seq = 0;
export function resetSeq(): void {
  seq = 0;
}

/** A client ledger entry with sane defaults. */
export function entry(type: string, amount: number, overrides: EntryOverrides = {}): Record<string, unknown> {
  seq++;
  const e: Record<string, unknown> = {
    id: overrides.id ?? uuid7(seq),
    type,
    amount,
    balanceAfter: overrides.balanceAfter ?? 0,
    createdAt: overrides.createdAt ?? NOW - 60_000 + seq * 1000,
    deviceId: overrides.deviceId ?? 'device-test',
    refId: overrides.refId === undefined ? null : overrides.refId,
  };
  if (overrides.lang !== undefined) e['lang'] = overrides.lang;
  return e;
}
