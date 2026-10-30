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
import { claimUsername as claimUsernameHandler } from './handlers/claimUsername';
import {
  createCoopRoom as createCoopRoomHandler,
  expireRooms as expireRoomsHandler,
  finishCoopRoom as finishCoopRoomHandler,
  joinCoopRoom as joinCoopRoomHandler,
  leaveCoopRoom as leaveCoopRoomHandler,
  startCoopRoom as startCoopRoomHandler,
} from './handlers/coop';
import { deleteAccount as deleteAccountHandler } from './handlers/deleteAccount';
import { publishPuzzle as publishPuzzleHandler } from './handlers/publishPuzzle';
import { rebuildManifests as rebuildManifestsHandler } from './handlers/rebuildManifests';
import { handleRevenueCatWebhook } from './handlers/revenuecat';
import { serverTime as serverTimeHandler } from './handlers/serverTime';
import { sendStreakReminders } from './handlers/streakReminders';
import { submitDaily as submitDailyHandler } from './handlers/submitDaily';
import { syncLedger as syncLedgerHandler } from './handlers/syncLedger';
import { trophyLeaderboard as trophyLeaderboardHandler } from './handlers/trophyLeaderboard';
import {
  cancelMatch as cancelMatchHandler,
  createMatch as createMatchHandler,
  expireMatches as expireMatchesHandler,
  findMatch as findMatchHandler,
  finishMatch as finishMatchHandler,
  joinMatch as joinMatchHandler,
  leaveMatch as leaveMatchHandler,
  reportProgress as reportProgressHandler,
  startMatch as startMatchHandler,
} from './handlers/versus';
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

export const claimUsername = onCall({ enforceAppCheck }, (request) =>
  claimUsernameHandler({ db: deps().db, users: deps().users }, requireAuth(request).uid, request.data, Date.now()),
);

export const deleteAccount = onCall({ enforceAppCheck }, (request) => deleteAccountHandler({ db: deps().db, users: deps().users }, requireAuth(request).uid));

export const streakReminders = onSchedule({ schedule: 'every 1 hours', timeZone: 'UTC', timeoutSeconds: 540 }, async () => {
  const result = await sendStreakReminders({ db: deps().db, messaging: deps().messaging }, Date.now());
  logger.info('streak reminders', result);
});

export const calibrateClues = onSchedule({ schedule: '0 3 * * *', timeZone: 'UTC', timeoutSeconds: 540, memory: '1GiB' }, async () => {
  const result = await calibrateCluesHandler(deps().db, Date.now());
  logger.info('clue calibration', result);
});

// --- Multiplayer: versus races, trophies, co-op rooms (README "Multiplayer") ---

export const createMatch = onCall({ enforceAppCheck }, (request) => createMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const joinMatch = onCall({ enforceAppCheck }, (request) => joinMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const findMatch = onCall({ enforceAppCheck }, (request) => findMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const startMatch = onCall({ enforceAppCheck }, (request) => startMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const reportProgress = onCall({ enforceAppCheck }, (request) => reportProgressHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const finishMatch = onCall({ enforceAppCheck }, (request) => finishMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const leaveMatch = onCall({ enforceAppCheck }, (request) => leaveMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const cancelMatch = onCall({ enforceAppCheck }, (request) => cancelMatchHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const trophyLeaderboard = onCall({ enforceAppCheck }, (request) => trophyLeaderboardHandler(deps().db, requireAuth(request).uid, request.data));

export const expireMatches = onSchedule({ schedule: 'every 1 minutes', timeZone: 'UTC', timeoutSeconds: 300 }, async () => {
  const result = await expireMatchesHandler({ db: deps().db }, Date.now());
  if (result.cancelled + result.forfeited + result.drawn + result.queueEntriesDeleted > 0) logger.info('expired matches', result);
});

export const createCoopRoom = onCall({ enforceAppCheck }, (request) => createCoopRoomHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const joinCoopRoom = onCall({ enforceAppCheck }, (request) => joinCoopRoomHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const startCoopRoom = onCall({ enforceAppCheck }, (request) => startCoopRoomHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const leaveCoopRoom = onCall({ enforceAppCheck }, (request) => leaveCoopRoomHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));
export const finishCoopRoom = onCall({ enforceAppCheck }, (request) => finishCoopRoomHandler({ db: deps().db }, requireAuth(request).uid, request.data, Date.now()));

export const expireRooms = onSchedule({ schedule: 'every 15 minutes', timeZone: 'UTC', timeoutSeconds: 300 }, async () => {
  const result = await expireRoomsHandler({ db: deps().db }, Date.now());
  if (result.expired > 0) logger.info('expired co-op rooms', result);
});
