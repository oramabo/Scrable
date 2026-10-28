import { sendStreakReminders } from '../src/handlers/streakReminders';
import { FakeFirestore } from './fakeFirestore';
import { FakeMessaging } from './fakes';

const NOW_18 = Date.UTC(2026, 9, 30, 18, 20, 0);

describe('streakReminders', () => {
  test('messages users whose reminder hour is now and who have not played today', async () => {
    const db = new FakeFirestore({
      'users/played': { settings: { reminderHourUtc: 18 }, streak: { lastDate: '2026-10-30' }, fcmToken: 't-played' },
      'users/due-he': { settings: { reminderHourUtc: 18, uiLang: 'he' }, streak: { lastDate: '2026-10-29' }, fcmToken: 't-he' },
      'users/due-en': { settings: { reminderHourUtc: 18, uiLang: 'en' }, fcmToken: 't-en' },
      'users/no-token': { settings: { reminderHourUtc: 18 }, streak: { lastDate: '2026-10-29' } },
      'users/disabled': { settings: { reminderHourUtc: 18, remindersEnabled: false }, fcmToken: 't-disabled' },
      'users/stale': { settings: { reminderHourUtc: 18 }, fcmToken: 't-stale' },
      'users/other-hour': { settings: { reminderHourUtc: 9 }, fcmToken: 't-other' },
    });
    const messaging = new FakeMessaging();
    messaging.staleTokens.add('t-stale');
    const res = await sendStreakReminders({ db, messaging }, NOW_18);
    expect(res).toEqual({ hour: 18, date: '2026-10-30', candidates: 6, sent: 2, staleTokens: 1, failed: 0 });
    expect(messaging.sent.map((m) => m.token).sort()).toEqual(['t-en', 't-he']);
    expect(messaging.sent.find((m) => m.token === 't-he')?.notification.title).toBe('הרצף שלך בסיכון');
    expect(messaging.sent.find((m) => m.token === 't-en')?.notification.title).toBe('Your streak is at risk');
    expect(db.get('users/stale')).toMatchObject({ fcmToken: null });
  });
});
