/**
 * Firebase Functions (2nd gen) entry point. Handlers live in ./handlers and
 * are pure functions over the abstractions in ./lib so they can be unit-tested
 * without the emulator; this file only wires them to Firebase.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { calibrateClues as calibrateCluesHandler } from './handlers/calibrateClues';
import { deleteAccount as deleteAccountHandler } from './handlers/deleteAccount';
import { publishPuzzle as publishPuzzleHandler } from './handlers/publishPuzzle';
import { rebuildManifests as rebuildManifestsHandler } from './handlers/rebuildManifests';
import { handleRevenueCatWebhook } from './handlers/revenuecat';
import { serverTime as serverTimeHandler } from './handlers/serverTime';
import { sendStreakReminders } from './handlers/streakReminders';
import { submitDaily as submitDailyHandler } from './handlers/submitDaily';
import { syncLedger as syncLedgerHandler } from './handlers/syncLedger';
import { adminUserAdmin, requireAdmin, requireAuth, type UserAdmin } from './lib/auth';
import type { Db } from './lib/firestore';
import { adminDb } from './lib/firestoreAdmin';
import { adminMessaging, type Messaging } from './lib/messaging';
import { adminStorage, type ObjectStore } from './lib/storage';

initializeApp();
setGlobalOptions({ region: process.env['FUNCTIONS_REGION'] ?? 'europe-west1', maxInstances: 20 });

/** Shared secret RevenueCat sends in `Authorization: Bearer ...` (set with `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET`). */
const revenueCatSecret = defineSecret('REVENUECAT_WEBHOOK_SECRET');

/** App Check enforcement for player-facing callables; set ENFORCE_APP_CHECK=false in functions/.env.<project> for emulator/test projects. */
const enforceAppCheck = process.env['ENFORCE_APP_CHECK'] !== 'false';

interface Deps {
  db: Db;
  storage: ObjectStore;
  users: UserAdmin;
  messaging: Messaging;
}

let depsCache: Deps | undefined;
function deps(): Deps {
  depsCache ??= {
    db: adminDb(getFirestore()),
    storage: adminStorage(getStorage().bucket(), process.env['CDN_BASE_URL']),
    users: adminUserAdmin(getAuth()),
    messaging: adminMessaging(getMessaging()),
  };
  return depsCache;
}

export const revenuecatWebhook = onRequest({ secrets: [revenueCatSecret], cors: false }, async (req, res) => {
  const result = await handleRevenueCatWebhook(
    deps().db,
    revenueCatSecret.value(),
    { method: req.method, headers: req.headers, body: req.body as unknown },
    Date.now(),
  );
  if (result.status >= 400) logger.warn('revenuecat webhook rejected', { status: result.status, ...result.body });
  else logger.info('revenuecat webhook processed', result.body);
  res.status(result.status).json(result.body);
});

export const syncLedger = onCall({ enforceAppCheck }, (request) => syncLedgerHandler(deps().db, requireAuth(request).uid, request.data, Date.now()));

export const submitDaily = onCall({ enforceAppCheck }, (request) => submitDailyHandler(deps().db, requireAuth(request).uid, request.data, Date.now()));

export const serverTime = onCall({ enforceAppCheck: false }, () => serverTimeHandler(Date.now()));

export const publishPuzzle = onCall({ enforceAppCheck: false, memory: '512MiB', timeoutSeconds: 120 }, (request) => {
  const admin = requireAdmin(request);
  return publishPuzzleHandler({ db: deps().db, storage: deps().storage }, request.data, Date.now(), admin.uid);
});

export const rebuildManifests = onCall({ enforceAppCheck: false, memory: '512MiB', timeoutSeconds: 300 }, (request) => {
  requireAdmin(request);
  return rebuildManifestsHandler({ db: deps().db, storage: deps().storage }, request.data, Date.now());
});

export const deleteAccount = onCall({ enforceAppCheck }, (request) => deleteAccountHandler({ db: deps().db, users: deps().users }, requireAuth(request).uid));

export const streakReminders = onSchedule({ schedule: 'every 1 hours', timeZone: 'UTC', timeoutSeconds: 540 }, async () => {
  const result = await sendStreakReminders({ db: deps().db, messaging: deps().messaging }, Date.now());
  logger.info('streak reminders', result);
});

export const calibrateClues = onSchedule({ schedule: '0 3 * * *', timeZone: 'UTC', timeoutSeconds: 540, memory: '1GiB' }, async () => {
  const result = await calibrateCluesHandler(deps().db, Date.now());
  logger.info('clue calibration', result);
});
