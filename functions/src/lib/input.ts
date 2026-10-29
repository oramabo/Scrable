/** Small input-parsing helpers for callables: every failure is an `invalid-argument` HttpsError. */
import { HttpsError } from 'firebase-functions/v2/https';

export type Lang = 'he' | 'en';
export const LANGS: readonly Lang[] = ['he', 'en'];

export const PUZZLE_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
export const SHA256_HEX = /^[0-9a-f]{64}$/;
export const DOC_ID = /^[A-Za-z0-9_-]{1,64}$/;

export function bad(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

export function asObject(input: unknown, what = 'input'): Record<string, unknown> {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) bad(`${what} must be an object`);
  return input as Record<string, unknown>;
}

export function requireString(o: Record<string, unknown>, key: string, pattern: RegExp, hint?: string): string {
  const v = o[key];
  if (typeof v !== 'string' || !pattern.test(v)) bad(`${key} is invalid${hint ? ` (${hint})` : ''}`);
  return v;
}

export function optionalString(o: Record<string, unknown>, key: string, pattern: RegExp, hint?: string): string | undefined {
  const v = o[key];
  if (v === undefined || v === null) return undefined;
  return requireString(o, key, pattern, hint);
}

export function requireInt(o: Record<string, unknown>, key: string, min: number, max: number): number {
  const v = o[key];
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) bad(`${key} must be an integer between ${min} and ${max}`);
  return v;
}

export function optionalInt(o: Record<string, unknown>, key: string, min: number, max: number): number | undefined {
  const v = o[key];
  if (v === undefined || v === null) return undefined;
  return requireInt(o, key, min, max);
}

export function requireNumber(o: Record<string, unknown>, key: string, min: number, max: number): number {
  const v = o[key];
  if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max) bad(`${key} must be a number between ${min} and ${max}`);
  return v;
}

export function requireEnum<T extends string>(o: Record<string, unknown>, key: string, values: readonly T[]): T {
  const v = o[key];
  if (typeof v !== 'string' || !(values as readonly string[]).includes(v)) bad(`${key} must be one of ${values.join(', ')}`);
  return v as T;
}

export function requireLang(o: Record<string, unknown>, key = 'lang'): Lang {
  return requireEnum(o, key, LANGS);
}
