import {
  type DocumentSnapshot,
  FieldPath,
  type Firestore,
  type Query,
  type Transaction as AdminTransaction,
  type WhereFilterOp,
} from 'firebase-admin/firestore';

import { assertCollectionPath, assertDocPath, type Db, type DocData, type DocSnapshot, type Filter, type QueryOptions, type SetOptions, type Transaction } from './firestore';

function toSnapshot(snap: DocumentSnapshot): DocSnapshot {
  return {
    id: snap.id,
    path: snap.ref.path,
    exists: snap.exists,
    data: snap.exists ? (snap.data() as DocData) : undefined,
  };
}

function filtered(firestore: Firestore, collectionPath: string, filters: Filter[]): Query {
  assertCollectionPath(collectionPath);
  let q: Query = firestore.collection(collectionPath);
  for (const f of filters) q = q.where(f.field, f.op as WhereFilterOp, f.value);
  return q;
}

function buildQuery(firestore: Firestore, collectionPath: string, filters: Filter[], options?: QueryOptions): Query {
  let q = filtered(firestore, collectionPath, filters);
  if (options?.orderBy !== undefined) {
    if (options.startAfterId !== undefined) throw new Error('startAfterId cannot be combined with orderBy');
    // Firestore appends __name__ in the same direction implicitly, which is the tie-break the fake mirrors.
    q = q.orderBy(options.orderBy.field, options.orderBy.direction ?? 'asc');
  } else {
    q = q.orderBy(FieldPath.documentId());
    if (options?.startAfterId !== undefined) q = q.startAfter(options.startAfterId);
  }
  if (options?.limit !== undefined) q = q.limit(options.limit);
  return q;
}

function wrapTransaction(firestore: Firestore, t: AdminTransaction): Transaction {
  return {
    async get(path) {
      assertDocPath(path);
      return toSnapshot(await t.get(firestore.doc(path)));
    },
    set(path, data, options?: SetOptions) {
      assertDocPath(path);
      if (options?.merge) t.set(firestore.doc(path), data, { merge: true });
      else t.set(firestore.doc(path), data);
    },
    delete(path) {
      assertDocPath(path);
      t.delete(firestore.doc(path));
    },
  };
}

/** Production `Db` backed by firebase-admin. */
export function adminDb(firestore: Firestore): Db {
  return {
    async getDoc(path) {
      assertDocPath(path);
      return toSnapshot(await firestore.doc(path).get());
    },
    async setDoc(path, data, options) {
      assertDocPath(path);
      if (options?.merge) await firestore.doc(path).set(data, { merge: true });
      else await firestore.doc(path).set(data);
    },
    async deleteDoc(path) {
      assertDocPath(path);
      await firestore.doc(path).delete();
    },
    async queryDocs(collectionPath, filters = [], options) {
      const snap = await buildQuery(firestore, collectionPath, filters, options).get();
      return snap.docs.map(toSnapshot);
    },
    async countDocs(collectionPath, filters = []) {
      // No orderBy: an aggregation needs none, and a range filter combined with an id ordering would be rejected.
      const snap = await filtered(firestore, collectionPath, filters).count().get();
      return snap.data().count;
    },
    runTransaction(fn) {
      return firestore.runTransaction((t) => fn(wrapTransaction(firestore, t)));
    },
  };
}
