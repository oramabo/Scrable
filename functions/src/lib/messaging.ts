import type { Messaging as AdminMessaging } from 'firebase-admin/messaging';

export interface PushNotification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/** Push messaging abstraction (FCM in production). */
export interface Messaging {
  /** Sends to one device token. Rejects with `{code: 'messaging/registration-token-not-registered'}`-style errors on stale tokens. */
  send(token: string, notification: PushNotification): Promise<void>;
}

export function adminMessaging(messaging: AdminMessaging): Messaging {
  return {
    async send(token, notification) {
      await messaging.send({
        token,
        notification: { title: notification.title, body: notification.body },
        data: notification.data,
      });
    },
  };
}

export function isStaleTokenError(err: unknown): boolean {
  const code = typeof err === 'object' && err !== null ? (err as { code?: unknown }).code : undefined;
  return code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token';
}
