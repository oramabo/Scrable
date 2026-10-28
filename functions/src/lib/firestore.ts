/**
 * Minimal Firestore abstraction: exactly the operations the handlers need,
 * typed on plain JSON data. The production adapter (firestoreAdmin.ts) wraps
 * firebase-admin; tests use test/fakeFirestore.ts.
 *
 * Paths are slash-separated Firestore paths: documents have an even number of
 * segments (`users/u1`), collections an odd number (`users/u1/ledger`).
 */

export type DocData = Record<string, unknown>;

export type WhereOp = '<' | '<=' | '==' | '!=' | '>=' | '>' | 'in';

export interface Filter {
  field: string;
  op: WhereOp;
  value: unknown;
}

export interface DocSnapshot {
  readonly id: string;
  readonly path: string;
  readonly exists: boolean;
  /** Undefined when the document does not exist. */
  readonly data: DocData | undefined;
}

export interface QueryOptions {
  limit?: number;
  /** Order by document id and continue after this id (pagination). */
  startAfterId?: string;
}

export interface SetOptions {
  /** Deep-merge maps into the existing document instead of replacing it. */
  merge?: boolean;
}

/** Firestore transaction: every `get` must happen before the first write. */
export interface Transaction {
  get(path: string): Promise<DocSnapshot>;
  set(path: string, data: DocData, options?: SetOptions): void;
  delete(path: string): void;
}

export interface Db {
  getDoc(path: string): Promise<DocSnapshot>;
  setDoc(path: string, data: DocData, options?: SetOptions): Promise<void>;
  deleteDoc(path: string): Promise<void>;
  /** Documents of a collection matching all filters, ordered by document id. */
  queryDocs(collectionPath: string, filters?: Filter[], options?: QueryOptions): Promise<DocSnapshot[]>;
  countDocs(collectionPath: string, filters?: Filter[]): Promise<number>;
  runTransaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T>;
}

export function isDocPath(path: string): boolean {
  const segments = path.split('/');
  return segments.length % 2 === 0 && segments.every((s) => s.length > 0);
}

export function isCollectionPath(path: string): boolean {
  const segments = path.split('/');
  return segments.length % 2 === 1 && segments.every((s) => s.length > 0);
}

export function assertDocPath(path: string): void {
  if (!isDocPath(path)) throw new Error(`not a document path: ${path}`);
}

export function assertCollectionPath(path: string): void {
  if (!isCollectionPath(path)) throw new Error(`not a collection path: ${path}`);
}

/** Replaces characters Firestore does not allow in document ids. */
export function safeDocId(raw: string, maxLength = 200): string {
  const cleaned = raw.replace(/[^A-Za-z0-9_.:@~-]/g, '_').slice(0, maxLength);
  return cleaned.length === 0 || cleaned === '.' || cleaned === '..' ? '_' : cleaned;
}

function isPlainObject(v: unknown): v is DocData {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Deep-merges `source` into a copy of `target` the way `set(..., {merge: true})` does. */
export function deepMerge(target: DocData | undefined, source: DocData): DocData {
  const out: DocData = { ...(target ?? {}) };
  for (const [key, value] of Object.entries(source)) {
    const existing = out[key];
    if (isPlainObject(value) && isPlainObject(existing)) {
      out[key] = deepMerge(existing, value);
    } else if (isPlainObject(value)) {
      out[key] = deepMerge(undefined, value);
    } else {
      out[key] = value;
    }
  }
  return out;
}

/** Reads a dotted field path (`wallet.balance`) from document data. */
export function getField(data: DocData | undefined, fieldPath: string): unknown {
  let current: unknown = data;
  for (const part of fieldPath.split('.')) {
    if (!isPlainObject(current)) return undefined;
    current = current[part];
  }
  return current;
}

export function readNumber(data: DocData | undefined, fieldPath: string, fallback = 0): number {
  const v = getField(data, fieldPath);
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}

export function readString(data: DocData | undefined, fieldPath: string): string | undefined {
  const v = getField(data, fieldPath);
  return typeof v === 'string' ? v : undefined;
}
