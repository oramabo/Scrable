import type { Storage } from 'firebase-admin/storage';

type Bucket = ReturnType<Storage['bucket']>;

/** Object storage abstraction for published puzzles and manifests. */
export interface ObjectStore {
  /** Writes `data` as UTF-8 JSON at `path` with the given Cache-Control header. */
  putJson(path: string, data: unknown, options: { cacheControl: string }): Promise<void>;
  /** Public (CDN) URL of an object. */
  publicUrl(path: string): string;
}

/** Immutable, versioned files (puzzles). */
export const CACHE_IMMUTABLE = 'public, max-age=31536000, immutable';
/** Files that are rewritten in place (manifests, pack indexes). */
export const CACHE_SHORT = 'public, max-age=300';

export function joinUrl(base: string, path: string): string {
  return `${base.replace(/\/+$/, '')}/${path.replace(/^\/+/, '')}`;
}

/** Production store backed by the default Firebase Storage bucket. */
export function adminStorage(bucket: Bucket, cdnBaseUrl?: string): ObjectStore {
  const base = cdnBaseUrl && cdnBaseUrl.length > 0 ? cdnBaseUrl : `https://storage.googleapis.com/${bucket.name}`;
  return {
    async putJson(path, data, options) {
      await bucket.file(path).save(Buffer.from(JSON.stringify(data), 'utf8'), {
        contentType: 'application/json; charset=utf-8',
        resumable: false,
        metadata: { cacheControl: options.cacheControl },
      });
    },
    publicUrl(path) {
      return joinUrl(base, path);
    },
  };
}
