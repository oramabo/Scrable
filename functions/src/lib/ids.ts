/**
 * Random identifiers and invite codes. Randomness is injected (`random`
 * returns [0, 1)) so tests are deterministic; production passes a CSPRNG-backed
 * source (`secureRandom`).
 */
import { randomInt } from 'node:crypto';

export type RandomSource = () => number;

/** Cryptographically strong [0, 1) source for production. */
export const secureRandom: RandomSource = () => randomInt(0, 2 ** 48) / 2 ** 48;

const ID_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
/** Upper-case alphanumerics without the confusable 0/O and 1/I: still matches `^[A-Z0-9]{6}$`. */
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 6;
export const INVITE_CODE = /^[A-Z0-9]{6}$/;

function pick(alphabet: string, random: RandomSource): string {
  const i = Math.min(alphabet.length - 1, Math.max(0, Math.floor(random() * alphabet.length)));
  return alphabet[i] as string;
}

/** 20-character random document id. */
export function newId(random: RandomSource, length = 20): string {
  let out = '';
  for (let i = 0; i < length; i++) out += pick(ID_ALPHABET, random);
  return out;
}

/** 6-character invite code (`inviteCodes/{code}` guarantees uniqueness). */
export function newInviteCode(random: RandomSource): string {
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i++) out += pick(CODE_ALPHABET, random);
  return out;
}

/** Trims and upper-cases a user-typed code (spaces and dashes are ignored); undefined when it is not six alphanumerics. */
export function normalizeInviteCode(input: unknown): string | undefined {
  if (typeof input !== 'string') return undefined;
  const code = input.trim().toUpperCase().replace(/[\s-]/g, '');
  return INVITE_CODE.test(code) ? code : undefined;
}

export function inviteCodePath(code: string): string {
  return `inviteCodes/${code}`;
}
