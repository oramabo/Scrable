/**
 * Hourly job: nudges players whose reminder hour is now and who have not
 * played today's daily yet. Reads `users/*` with
 * `settings.reminderHourUtc == currentHour`, `streak.lastDate`, `fcmToken`.
 */
import * as logger from 'firebase-functions/logger';

import { type Db, getField, readString } from '../lib/firestore';
import { isStaleTokenError, type Messaging, type PushNotification } from '../lib/messaging';
import { isoDate } from '../lib/time';

const PAGE = 200;

export interface ReminderDeps {
  db: Db;
  messaging: Messaging;
}

export interface ReminderResult {
  hour: number;
  date: string;
  candidates: number;
  sent: number;
  staleTokens: number;
  failed: number;
}

export function reminderNotification(uiLang: string | undefined): PushNotification {
  if (uiLang === 'en') {
    return { title: 'Your streak is at risk', body: "Today's daily arrowword is waiting for you.", data: { route: '/daily' } };
  }
  return { title: 'הרצף שלך בסיכון', body: 'התשחץ היומי מחכה לך.', data: { route: '/daily' } };
}

export async function sendStreakReminders(deps: ReminderDeps, now: number): Promise<ReminderResult> {
  const hour = new Date(now).getUTCHours();
  const date = isoDate(now);
  const result: ReminderResult = { hour, date, candidates: 0, sent: 0, staleTokens: 0, failed: 0 };
  let startAfterId: string | undefined;
  for (;;) {
    const users = await deps.db.queryDocs('users', [{ field: 'settings.reminderHourUtc', op: '==', value: hour }], { limit: PAGE, startAfterId });
    for (const user of users) {
      result.candidates++;
      if (getField(user.data, 'settings.remindersEnabled') === false) continue;
      if (readString(user.data, 'streak.lastDate') === date) continue;
      const token = readString(user.data, 'fcmToken');
      if (token === undefined || token.length === 0) continue;
      try {
        await deps.messaging.send(token, reminderNotification(readString(user.data, 'settings.uiLang')));
        result.sent++;
      } catch (err) {
        if (isStaleTokenError(err)) {
          result.staleTokens++;
          await deps.db.setDoc(user.path, { fcmToken: null }, { merge: true });
        } else {
          result.failed++;
          logger.warn('streak reminder failed', { uid: user.id, error: err instanceof Error ? err.message : String(err) });
        }
      }
    }
    if (users.length < PAGE) break;
    startAfterId = users[users.length - 1]?.id;
  }
  return result;
}
