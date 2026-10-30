/**
 * Usernames: validation, the uniqueness key and the name other players see.
 * A username is claimed through the `claimUsername` callable once a player has
 * linked Google or Apple sign-in; it is stored as `users/{uid}.username`
 * (written by functions only) and reserved in `usernames/{key}`.
 */
import { type DocData, type DocSnapshot, readString } from './firestore';

export const USERNAME_MIN = 3;
export const USERNAME_MAX = 20;

/** Hebrew letters (no niqqud), Latin letters and digits; `_` and `.` inside only, never doubled. */
const USERNAME_PATTERN = /^[A-Za-z0-9א-ת](?:[A-Za-z0-9א-ת]|[_.](?=[A-Za-z0-9א-ת]))*$/;

/** Compared on the key, so `Admin`, `ADMIN` and `ad.min` are all taken. */
const RESERVED = ['admin', 'administrator', 'moderator', 'support', 'system', 'official', 'chetz', 'player', 'חץ', 'מנהל', 'מנהלת', 'תמיכה', 'שחקן'];

/** Hebrew final letters map to their regular form so ספר and ספר-with-ף cannot coexist. */
const FINAL_TO_REGULAR: Record<string, string> = { ך: 'כ', ם: 'מ', ן: 'נ', ף: 'פ', ץ: 'צ' };

export type UsernameProblem = 'length' | 'characters' | 'reserved';

/** Uniqueness key: lower case, final letters regularised, `_` and `.` ignored. */
export function usernameKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/[ךםןףץ]/g, (ch) => FINAL_TO_REGULAR[ch] ?? ch)
    .replace(/[_.]/g, '');
}

export function usernameProblem(name: string): UsernameProblem | undefined {
  if (name.length < USERNAME_MIN || name.length > USERNAME_MAX) return 'length';
  if (!USERNAME_PATTERN.test(name)) return 'characters';
  const key = usernameKey(name);
  if (RESERVED.some((r) => usernameKey(r) === key)) return 'reserved';
  return undefined;
}

export function usernameDocPath(key: string): string {
  return `usernames/${key}`;
}

/** The name shown to other players: the claimed username, else the free-text profile name, else "Player". */
export function displayNameOf(user: DocSnapshot | { data: DocData | undefined }): string {
  const username = readString(user.data, 'username')?.trim();
  if (username !== undefined && username.length > 0) return username;
  const name = readString(user.data, 'profile.displayName')?.trim();
  return name !== undefined && name.length > 0 ? name.slice(0, 40) : 'Player';
}
