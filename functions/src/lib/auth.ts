import { timingSafeEqual } from 'node:crypto';

import type { Auth } from 'firebase-admin/auth';
import { type CallableRequest, HttpsError } from 'firebase-functions/v2/https';

export interface AuthContext {
  uid: string;
  token: Record<string, unknown>;
}

type AuthLike = Pick<CallableRequest<unknown>, 'auth'>;

/** The signed-in caller, or `unauthenticated`. */
export function requireAuth(request: AuthLike): AuthContext {
  const auth = request.auth;
  if (!auth || typeof auth.uid !== 'string' || auth.uid.length === 0) {
    throw new HttpsError('unauthenticated', 'Sign in is required.');
  }
  return { uid: auth.uid, token: (auth.token ?? {}) as unknown as Record<string, unknown> };
}

/** A signed-in caller carrying the custom claim `admin: true`, or `permission-denied`. */
export function requireAdmin(request: AuthLike): AuthContext {
  const ctx = requireAuth(request);
  if (ctx.token['admin'] !== true) {
    throw new HttpsError('permission-denied', 'This operation requires the admin role.');
  }
  return ctx;
}

/** Extracts the token of an `Authorization: Bearer <token>` header. */
export function bearerToken(header: string | string[] | undefined): string | undefined {
  const value = Array.isArray(header) ? header[0] : header;
  if (typeof value !== 'string') return undefined;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(value);
  return match ? match[1] : undefined;
}

/** Constant-time string comparison (both sides hashed to equal length first is unnecessary: lengths leak nothing useful here). */
export function secretsEqual(provided: string | undefined, expected: string | undefined): boolean {
  if (typeof provided !== 'string' || typeof expected !== 'string' || expected.length === 0) return false;
  const a = Buffer.from(provided, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Auth user administration (deleteAccount); abstracted for tests. */
export interface UserAdmin {
  deleteUser(uid: string): Promise<void>;
}

export function adminUserAdmin(auth: Auth): UserAdmin {
  return {
    async deleteUser(uid) {
      try {
        await auth.deleteUser(uid);
      } catch (err) {
        const code = typeof err === 'object' && err !== null ? (err as { code?: unknown }).code : undefined;
        if (code === 'auth/user-not-found') return;
        throw err;
      }
    },
  };
}
