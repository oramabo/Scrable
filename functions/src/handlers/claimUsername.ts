/**
 * `claimUsername` callable: reserves a unique username for a player who has
 * linked Google or Apple sign-in (anonymous accounts cannot claim one, so a
 * name always belongs to a recoverable account). Renaming releases the old
 * name in the same transaction.
 */
import { HttpsError } from 'firebase-functions/v2/https';

import type { UserAdmin } from '../lib/auth';
import type { Db } from '../lib/firestore';
import { readString } from '../lib/firestore';
import { usernameDocPath, usernameKey, usernameProblem } from '../lib/username';

export interface ClaimUsernameDeps {
  db: Db;
  users: UserAdmin;
}

export interface ClaimUsernameResult {
  username: string;
}

/** Linked sign-in providers that may hold a username. */
export const ACCOUNT_PROVIDERS = ['google.com', 'apple.com'] as const;

export async function claimUsername(deps: ClaimUsernameDeps, uid: string, input: unknown, now: number): Promise<ClaimUsernameResult> {
  // The account record, not the token's last sign-in method: linking keeps the uid.
  const linked = await deps.users.providerIds(uid);
  if (!linked.some((p) => (ACCOUNT_PROVIDERS as readonly string[]).includes(p))) {
    throw new HttpsError('failed-precondition', 'Sign in with Google or Apple before choosing a username.');
  }
  const raw = typeof input === 'object' && input !== null ? (input as Record<string, unknown>)['username'] : undefined;
  if (typeof raw !== 'string') throw new HttpsError('invalid-argument', '`username` must be a string');
  const username = raw.trim();
  const problem = usernameProblem(username);
  if (problem) throw new HttpsError('invalid-argument', `username is not allowed: ${problem}`, { reason: problem });
  const key = usernameKey(username);

  return deps.db.runTransaction(async (tx) => {
    const claim = await tx.get(usernameDocPath(key));
    const owner = readString(claim.data, 'uid');
    if (claim.exists && owner !== uid) throw new HttpsError('already-exists', 'This username is taken.', { reason: 'taken' });
    const user = await tx.get(`users/${uid}`);
    const previous = readString(user.data, 'username');
    if (previous !== undefined && usernameKey(previous) !== key) tx.delete(usernameDocPath(usernameKey(previous)));
    tx.set(usernameDocPath(key), { uid, username, updatedAt: now });
    tx.set(`users/${uid}`, { username, usernameUpdatedAt: now, profile: { displayName: username } }, { merge: true });
    return { username };
  });
}
