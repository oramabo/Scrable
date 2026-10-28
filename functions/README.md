# `functions/` — Firebase Functions (2nd gen, TypeScript)

Backend for the Chetz arrowword app: wallet ledger validation, RevenueCat
purchases, daily leaderboard, content publishing and scheduled jobs. Runtime
Node 20, `firebase-functions` v6, `firebase-admin` v13.

## Layout

```
src/index.ts            Firebase wiring only (onCall / onRequest / onSchedule, secrets, App Check)
src/handlers/*.ts       Pure handlers: (deps, uid/input, now) → result; throw HttpsError
src/lib/firestore.ts    Db abstraction (getDoc/setDoc/queryDocs/countDocs/runTransaction)
src/lib/firestoreAdmin.ts  firebase-admin implementation of Db
src/lib/storage.ts      ObjectStore abstraction (+ admin implementation)
src/lib/messaging.ts    FCM abstraction;  src/lib/auth.ts  requireAuth/requireAdmin, UserAdmin
src/lib/validate.ts     ajv 2020-12 instance loaded with ../schema/*.schema.json
src/lib/puzzleCodec.ts  Port of PuzzleCodec: xor1 decode, canonical JSON, checksum, solutionHash
src/economy.ts          Coin products, hint prices, caps (mirror of docs/GAME_PLAN.md §3.5/§4.1/§4.2)
test/                   jest (ts-jest) with an in-memory Firestore fake
scripts/sync-schema.mjs Copies ../schema/*.schema.json into functions/schema (part of `npm run build`)
```

## Functions

| Export | Kind | Auth | What it does |
|--------|------|------|--------------|
| `revenuecatWebhook` | HTTPS | `Authorization: Bearer $REVENUECAT_WEBHOOK_SECRET` | INITIAL_PURCHASE / NON_RENEWING_PURCHASE / RENEWAL of `coins_*` products → idempotent `users/{uid}/ledger/rc_{eventId}` (`purchase_bundle`) and `wallet.balance` increment in a transaction; CANCELLATION (refund) / EXPIRATION by customer support of a coin product → `rc_{eventId}_refund`; `entitlement_ids` mirrored to `users/{uid}.entitlements` for every event. 401 bad secret, 400 malformed, 405 non-POST, 200 after processing. |
| `syncLedger` | callable | user | `{entries: LedgerEntry[]}` (≤ 100). Each entry is validated against `schema/ledger-entry.schema.json` and `src/economy.ts` (earn caps, once-per-puzzle, per-day caps, spend price caps, no negative balance, server-only types rejected). Accepted and rejected entries are stored under `users/{uid}/ledger/{id}` with `server.status`; replays are idempotent. Returns `{accepted, rejected: [{id, reason}], balance}`. A new wallet is seeded with the `starting_wallet` entry (200 coins) — the client must not send its own starting-wallet entry. `reconcile` entries are stored but never move coins. |
| `submitDaily` | callable | user (+ App Check) | Leaderboard submission: date within ±2 days of the server date, one entry per uid, `elapsedMs ≥ 700 ms × letterCells`, `solutionHash` equal to the published daily's. `score = elapsed + 20 s·letters + 60 s·words + 15 s·checks + {relaxed 15 %, normal 5 %, newspaper 0}·elapsed`. Returns `{score, rank}`. |
| `serverTime` | callable | none | `{nowMs, date}` so the app never trusts the device clock for the daily date. |
| `publishPuzzle` | callable | `admin` claim | `{puzzle, lang, solutionHash?, pack?: {index?, title?, free?}}` (`title` may be a string or `{he, en}`; `solutionHash` comes from `publish-index.json`). Validates against `schema/puzzle.schema.json`, recomputes and verifies `meta.checksum`, decodes the `xor1` solution to compute `solutionHash` (a publisher-supplied one is cross-checked), uploads the immutable file to `puzzles/{lang}/daily/{variant}/{date}.v{n}.json` or `puzzles/{lang}/packs/{packId}/{NN}.v{n}.json`, writes `dailies/{lang}_{date}_{variant}` (puzzleId, letterCells, solutionHash, …) and updates the manifest source docs `manifests/{lang}_daily` / `manifests/{lang}_packs`. Tutorial/practice puzzles are refused (they ship inside the app). |
| `rebuildManifests` | callable | `admin` claim | `{lang}` → writes `manifests/{lang}/daily.json`, `manifests/{lang}/packs.json` and one `puzzles/{lang}/packs/{packId}/pack.v1.json` per pack, in the same shape and with the same CDN-relative urls as `chetz_gen manifest`, each validated against the manifest schemas (5-minute cache). |
| `deleteAccount` | callable | user | Deletes `users/{uid}/{progress,ledger,daily,claims}/*`, `users/{uid}` and the Auth user. |
| `streakReminders` | scheduled hourly | — | FCM nudge to users with `settings.reminderHourUtc == hour` whose `streak.lastDate != today`. |
| `calibrateClues` | scheduled 03:00 UTC | — | Aggregates `telemetry/wordSolved/events/*` into `clueStats/{clueId}` `{n, medianRelTime, hintRate}` (stub of the §5.3 self-calibration). |

## Develop

```sh
cd functions
npm ci
npm run build        # sync schemas + tsc → lib/
npm test             # jest, no emulator needed (in-memory Firestore fake)
npm run typecheck    # type-checks tests too
```

Tests cover webhook idempotency and auth, ledger caps / once-per-puzzle /
below-zero spends, leaderboard plausibility and the score formula, schema and
checksum rejection in `publishPuzzle`, manifest generation, clue aggregation,
account deletion, reminders — and that the TypeScript codec port reproduces the
Dart checksum and solution hash of the fixtures in `../schema/fixtures`.

## Deploy

All Firebase configuration lives in `../firebase/` (`firebase.json`,
`firestore.rules`, `firestore.indexes.json`, `storage.rules`,
`remoteconfig.template.json`). Run the CLI from that directory.

```sh
cd firebase
cp .firebaserc.example .firebaserc   # then edit the project ids, or: firebase use --add
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET   # shared secret configured in the RevenueCat webhook (Authorization header)
firebase functions:secrets:set DAILY_SEED_SECRET           # placeholder: HMAC key for daily seeds, used by the generateDailiesJob (not implemented yet)
firebase deploy --only functions,firestore,storage,remoteconfig
```

Environment (non-secret) settings go in `functions/.env.<project-id>` — see
`.env.example`: `FUNCTIONS_REGION` (default `europe-west1`), `CDN_BASE_URL`
(public base URL of the bucket or the CDN in front of it; used in manifests),
`ENFORCE_APP_CHECK` (`false` on dev projects without App Check). The CDN
manifests themselves carry CDN-relative paths (the app prefixes its
`cdnBaseUrl`), so `CDN_BASE_URL` only affects the absolute `url` fields stored
in Firestore for the admin tool.

### Publishing flow

1. `dart run tools/generate/bin/chetz_gen.dart --content content dailies|pack ...` generates puzzles and
   `chetz_gen manifest` writes `content/{lang}/puzzles/manifests/publish-index.json` (one row per puzzle with
   `solutionHash`, `letterCells`, `checksum`).
2. For each approved puzzle the admin tool calls `publishPuzzle({puzzle, lang, solutionHash})`.
3. `rebuildManifests({lang})` republishes the CDN manifests. Hiding a puzzle = removing its entry from
   `manifests/{lang}_daily|_packs` and rebuilding.

Give an editor the admin role once:

```sh
node -e "require('firebase-admin').initializeApp(); require('firebase-admin').auth().setCustomUserClaims(process.argv[1], {admin: true}).then(()=>console.log('ok'))" <uid>
```

### Emulator

```sh
cd firebase && firebase emulators:start --only functions,firestore,storage,auth
```

The emulator needs Java and `firebase-tools`; the unit tests do not.

## Data model touched by the functions

```
users/{uid}                      wallet{balance, updatedAt}, entitlements{premium, remove_ads}, entitlementsMeta, settings, streak, fcmToken
users/{uid}/ledger/{id}          ledger entries (client UUID v7 or rc_* / starting_wallet) + server{status, reason, appliedAmount, ...}
users/{uid}/claims/{key}         once-per-ref markers `{type}~{refId}` and per-day counters `{type}~day~{YYYY-MM-DD}`
dailies/{lang}_{date}_{variant}  puzzleId, letterCells, solutionHash, checksum, version, url, publishedAt
leaderboards/{lang}_{date}_{variant}/entries/{uid}   score, elapsedMs, hints, mode, submittedAt
manifests/{lang}_daily | {lang}_packs                 source documents for the CDN manifests
telemetry/wordSolved/events/{id}  clueId, relTime, hinted, lang   →   clueStats/{clueId}
```
