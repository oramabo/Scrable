/**
 * In-memory Firestore fake implementing the `Db` abstraction with the
 * semantics the handlers rely on: deep merge on `set(..., {merge: true})`,
 * document-id ordering and pagination, simple where filters, and
 * transactions that buffer writes and refuse reads after the first write
 * (as the real SDK does). Rejects `undefined` field values like firebase-admin.
 */
import {
  assertCollectionPath,
  assertDocPath,
  type Db,
  deepMerge,
  type DocData,
  type DocSnapshot,
  type Filter,
  getField,
  type QueryOptions,
  type SetOptions,
  type Transaction,
  type WhereOp,
} from '../src/lib/firestore';

function clone<T>(v: T): T {
  return v === undefined ? v : (JSON.parse(JSON.stringify(v)) as T);
}

function assertNoUndefined(value: unknown, where: string): void {
  if (value === undefined) throw new Error(`undefined field value at ${where} (Firestore rejects undefined)`);
  if (Array.isArray(value)) value.forEach((v, i) => assertNoUndefined(v, `${where}[${i}]`));
  else if (typeof value === 'object' && value !== null) {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) assertNoUndefined(v, `${where}.${k}`);
  }
}

function compare(a: unknown, b: unknown): number | undefined {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  if (typeof a === 'string' && typeof b === 'string') return a < b ? -1 : a > b ? 1 : 0;
  return undefined;
}

function same(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function matches(actual: unknown, op: WhereOp, expected: unknown): boolean {
  switch (op) {
    case '==':
      return actual !== undefined && same(actual, expected);
    case '!=':
      return actual !== undefined && !same(actual, expected);
    case 'in':
      return Array.isArray(expected) && expected.some((e) => same(e, actual));
    default: {
      const c = compare(actual, expected);
      if (c === undefined) return false;
      if (op === '<') return c < 0;
      if (op === '<=') return c <= 0;
      if (op === '>') return c > 0;
      return c >= 0;
    }
  }
}

export class FakeFirestore implements Db {
  readonly docs = new Map<string, DocData>();
  writeCount = 0;

  constructor(seed: Record<string, DocData> = {}) {
    for (const [path, data] of Object.entries(seed)) {
      assertDocPath(path);
      this.docs.set(path, clone(data));
    }
  }

  /** Plain data of a document (test helper). */
  get(path: string): DocData | undefined {
    return clone(this.docs.get(path));
  }

  /** Paths of the documents directly inside a collection (test helper). */
  list(collectionPath: string): string[] {
    const prefix = `${collectionPath}/`;
    return [...this.docs.keys()].filter((p) => p.startsWith(prefix) && !p.slice(prefix.length).includes('/')).sort();
  }

  snapshot(path: string): DocSnapshot {
    assertDocPath(path);
    const data = this.docs.get(path);
    return { id: path.slice(path.lastIndexOf('/') + 1), path, exists: data !== undefined, data: clone(data) };
  }

  async getDoc(path: string): Promise<DocSnapshot> {
    return this.snapshot(path);
  }

  async setDoc(path: string, data: DocData, options?: SetOptions): Promise<void> {
    this.applySet(path, data, options);
  }

  async deleteDoc(path: string): Promise<void> {
    assertDocPath(path);
    this.docs.delete(path);
  }

  async queryDocs(collectionPath: string, filters: Filter[] = [], options?: QueryOptions): Promise<DocSnapshot[]> {
    assertCollectionPath(collectionPath);
    let rows = this.list(collectionPath).map((p) => this.snapshot(p));
    rows = rows.filter((r) => filters.every((f) => matches(getField(r.data, f.field), f.op, f.value)));
    const orderBy = options?.orderBy;
    if (orderBy !== undefined) {
      if (options?.startAfterId !== undefined) throw new Error('startAfterId cannot be combined with orderBy');
      const sign = orderBy.direction === 'desc' ? -1 : 1;
      rows = rows.filter((r) => getField(r.data, orderBy.field) !== undefined);
      rows.sort((a, b) => {
        const c = compare(getField(a.data, orderBy.field), getField(b.data, orderBy.field)) ?? 0;
        return c !== 0 ? sign * c : sign * (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
      });
    }
    const after = options?.startAfterId;
    if (after !== undefined) rows = rows.filter((r) => r.id > after);
    if (options?.limit !== undefined) rows = rows.slice(0, options.limit);
    return rows;
  }

  async countDocs(collectionPath: string, filters: Filter[] = []): Promise<number> {
    return (await this.queryDocs(collectionPath, filters)).length;
  }

  async runTransaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T> {
    const buffered: Array<() => void> = [];
    let writing = false;
    const tx: Transaction = {
      get: async (path) => {
        if (writing) throw new Error(`transaction read of ${path} after a write; Firestore requires all reads before writes`);
        return this.snapshot(path);
      },
      set: (path, data, options) => {
        writing = true;
        assertDocPath(path);
        assertNoUndefined(data, path);
        const snapshot = clone(data);
        buffered.push(() => this.applySet(path, snapshot, options));
      },
      delete: (path) => {
        writing = true;
        assertDocPath(path);
        buffered.push(() => {
          this.docs.delete(path);
        });
      },
    };
    const result = await fn(tx);
    for (const write of buffered) write();
    return result;
  }

  private applySet(path: string, data: DocData, options?: SetOptions): void {
    assertDocPath(path);
    assertNoUndefined(data, path);
    const existing = this.docs.get(path);
    this.docs.set(path, options?.merge ? deepMerge(existing, clone(data)) : clone(data));
    this.writeCount++;
  }
}
