import type { UserAdmin } from '../src/lib/auth';
import type { Messaging, PushNotification } from '../src/lib/messaging';
import type { ObjectStore } from '../src/lib/storage';

export class FakeStorage implements ObjectStore {
  readonly objects = new Map<string, { data: unknown; cacheControl: string; contentType?: string }>();
  constructor(readonly base = 'https://cdn.test') {}
  async putBytes(path: string, data: Uint8Array, options: { cacheControl: string; contentType: string }): Promise<void> {
    this.objects.set(path, { data, cacheControl: options.cacheControl, contentType: options.contentType });
  }

  async putJson(path: string, data: unknown, options: { cacheControl: string }): Promise<void> {
    this.objects.set(path, { data: JSON.parse(JSON.stringify(data)) as unknown, cacheControl: options.cacheControl });
  }
  publicUrl(path: string): string {
    return `${this.base}/${path}`;
  }
  json(path: string): unknown {
    return this.objects.get(path)?.data;
  }
}

export class FakeMessaging implements Messaging {
  readonly sent: Array<{ token: string; notification: PushNotification }> = [];
  readonly staleTokens = new Set<string>();
  async send(token: string, notification: PushNotification): Promise<void> {
    if (this.staleTokens.has(token)) {
      throw Object.assign(new Error('Requested entity was not found.'), { code: 'messaging/registration-token-not-registered' });
    }
    this.sent.push({ token, notification });
  }
}

export class FakeUserAdmin implements UserAdmin {
  readonly deleted: string[] = [];
  /** Linked sign-in providers per uid (anonymous when absent). */
  readonly providers: Record<string, string[]> = {};
  async deleteUser(uid: string): Promise<void> {
    this.deleted.push(uid);
  }
  async providerIds(uid: string): Promise<string[]> {
    return this.providers[uid] ?? [];
  }
}
