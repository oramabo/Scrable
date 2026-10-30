/** `deleteAccount` callable: removes the caller's Firestore data and auth user. */
import type { UserAdmin } from '../lib/auth';
import { type Db, readString } from '../lib/firestore';
import { usernameDocPath, usernameKey } from '../lib/username';

export const USER_SUBCOLLECTIONS = ['progress', 'ledger', 'daily', 'claims'] as const;
const PAGE = 200;

export interface DeleteAccountDeps {
  db: Db;
  users: UserAdmin;
}

export interface DeleteAccountResult {
  deletedDocs: number;
}

export async function deleteAccount(deps: DeleteAccountDeps, uid: string): Promise<DeleteAccountResult> {
  let deletedDocs = 0;
  for (const sub of USER_SUBCOLLECTIONS) {
    for (;;) {
      const docs = await deps.db.queryDocs(`users/${uid}/${sub}`, [], { limit: PAGE });
      if (docs.length === 0) break;
      await Promise.all(docs.map((d) => deps.db.deleteDoc(d.path)));
      deletedDocs += docs.length;
      if (docs.length < PAGE) break;
    }
  }
  const user = await deps.db.getDoc(`users/${uid}`);
  const username = readString(user.data, 'username');
  if (username !== undefined) {
    const claim = usernameDocPath(usernameKey(username));
    if (readString((await deps.db.getDoc(claim)).data, 'uid') === uid) {
      await deps.db.deleteDoc(claim);
      deletedDocs++;
    }
  }
  if (user.exists) {
    await deps.db.deleteDoc(`users/${uid}`);
    deletedDocs++;
  }
  // Last, so a failed Firestore cleanup can be retried by the still-signed-in user.
  await deps.users.deleteUser(uid);
  return { deletedDocs };
}
