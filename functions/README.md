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
src/economy.ts          Coin products, hint prices, caps (mirror of docs/GAME_PLAN.md §3.5/§4.1/§4.2), multiplayer rewards + trophy constants
src/lib/season.ts       Season-pass calendar (seasonIdFor / seasonBounds);  src/lib/trophies.ts  trophy (Elo-style) formula
src/lib/rewards.ts      Idempotent server rewards (coins + XP + season points) inside a transaction, per-day caps
src/lib/ids.ts          Random ids and 6-character invite codes;  src/lib/puzzleLookup.ts  matchPool / dailies / puzzleIndex resolution
src/handlers/versus.ts  Versus races (matches, matchmaking, settlement, expiry);  src/handlers/coop.ts  co-op rooms
src/handlers/trophyLeaderboard.ts  Top trophies + caller rank
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
| `publishPuzzle` | callable | `admin` claim | `{puzzle, lang, solutionHash?, pack?: {index?, title?, free?}}` (`title` may be a string or `{he, en}`; `solutionHash` comes from `publish-index.json`). Validates against `schema/puzzle.schema.json`, recomputes and verifies `meta.checksum`, decodes the `xor1` solution to compute `solutionHash` (a publisher-supplied one is cross-checked), uploads the immutable file to `puzzles/{lang}/daily/{variant}/{date}.v{n}.json` or `puzzles/{lang}/packs/{packId}/{NN}.v{n}.json`, writes `dailies/{lang}_{date}_{variant}` (puzzleId, letterCells, solutionHash, …), `puzzleIndex/{puzzleId}` (lookup record used by the multiplayer handlers) and updates the manifest source docs `manifests/{lang}_daily` / `manifests/{lang}_packs`. Tutorial/practice puzzles are refused (they ship inside the app). |
| `rebuildManifests` | callable | `admin` claim | `{lang}` → writes `manifests/{lang}/daily.json`, `manifests/{lang}/packs.json` and one `puzzles/{lang}/packs/{packId}/pack.v1.json` per pack, in the same shape and with the same CDN-relative urls as `chetz_gen manifest`, each validated against the manifest schemas (5-minute cache). |
| `claimUsername` | callable | user with Google/Apple linked | Reserves `{username}` case- and final-letter-insensitively in `usernames/{key}`, releases the previous name, writes `users/{uid}.username` (server-only field) and `profile.displayName`. Multiplayer and leaderboards show the username. |
| `deleteAccount` | callable | user | Deletes `users/{uid}/{progress,ledger,daily,claims}/*`, `users/{uid}`, the claimed username and the Auth user. |
| `createMatch` `joinMatch` `findMatch` `startMatch` `reportProgress` `finishMatch` `leaveMatch` `cancelMatch` | callable | user (+ App Check) | Versus races — see [Multiplayer](#multiplayer). |
| `trophyLeaderboard` | callable | user (+ App Check) | `{lang, limit≤100}` → top trophy entries + the caller's rank. |
| `expireMatches` | scheduled every minute | — | Closes matches past `expiresAt` (cancels lobbies, awards forfeits, draws unfinished races), deletes stale matchmaking entries. |
| `createCoopRoom` `joinCoopRoom` `startCoopRoom` `leaveCoopRoom` `finishCoopRoom` | callable | user (+ App Check) | Co-op rooms — see [Multiplayer](#multiplayer). |
| `expireRooms` | scheduled every 15 min | — | Closes co-op rooms idle for more than 2 hours. |
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
account deletion, reminders, the multiplayer flows (invite race end to end,
random matchmaking, cheat rejection, forfeit by expiry, trophy formula bounds,
season boundaries, co-op create/join/finish with idempotent rewards) — and that
the TypeScript codec port reproduces the Dart checksum and solution hash of the
fixtures in `../schema/fixtures`.

The Firestore rules can be smoke-tested against the emulator
(`firebase emulators:exec --only firestore --project demo-chetz "<script>"`);
the multiplayer rules were verified that way (members-only room reads,
own-cursor-only updates, cell writes with `by == auth.uid`, public trophy board,
hidden invite codes, server-only `trophies`/`xp`/`season`).

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
puzzleIndex/{puzzleId}           lang, kind, level, letterCells, solutionHash, checksum, version (every published puzzle)
users/{uid}                      + trophies, xp, season.{seasonId}.points, lastMatchAt, lastCoopAt   (server-only, see Multiplayer)
matches/{matchId}                schema/match.schema.json
matchQueue/{lang}_{level}/entries/{uid}   uid, status: waiting|matched, enqueuedAt, matchId?, matchedAt?, displayName
matchPool/{lang}_{level}         puzzles: [{puzzleId, letterCells, solutionHash?}]   (publisher-maintained)
inviteCodes/{code}               kind: match|coop, refId, createdBy, createdAt, expiresAt
trophyBoard/{lang}/entries/{uid} uid, trophies, displayName, updatedAt
coopRooms/{roomId}               schema/coop-room.schema.json;  coopRooms/{roomId}/cells/{cellIndex}  symbol, by, at (client-written)
```

## Multiplayer

Real-time play goes through Firestore listeners on the client and callables on
the server; the server owns every result. All callables require a signed-in
user and honour `ENFORCE_APP_CHECK` like the other player-facing functions.
Every call takes and returns plain JSON; times are server milliseconds.

### Versus races

Two players solve the same puzzle; only the progress percentage is shared,
never the grid. `matches/{matchId}` (shape: `schema/match.schema.json`) is
readable by its players and written only by the functions.

| Callable | Input | Output | Rules |
|----------|-------|--------|-------|
| `createMatch` | `{lang, level 1..9, puzzleId?}` | `{matchId, inviteCode, match}` | Puzzle = the given id (resolved through `matchPool/{lang}_{level}`, `dailies`, `puzzleIndex`; unknown → `not-found`) or a server pick (pool of the level → dailies of the level → any daily of the language). Six-character invite code (A–Z 2–9 without 0/O/1/I), unique via `inviteCodes/{code}`. Status `waiting`, expires after 30 min. |
| `joinMatch` | `{inviteCode}` | `{matchId, match}` | Case-insensitive. Second player joins → status `ready` (10 min to start). Full or non-waiting match → `failed-precondition`; the host re-joining is a no-op. |
| `findMatch` | `{lang, level}` | `{queued: true, lang, level}` or `{queued: false, matchId, match}` | Matchmaking: pops the oldest `waiting` entry of `matchQueue/{lang}_{level}/entries/*` enqueued within the last 2 minutes (not the caller's), creates the match with status `ready`, `mode: 'random'`, `inviteCode: null`, host = the player who queued first, and marks both entries `{status: 'matched', matchId}`; otherwise enqueues the caller. A queued client listens to its own entry (readable by its owner) or polls `findMatch`, which returns the match while it is `ready`/`running`. |
| `startMatch` | `{matchId}` | `{matchId, status, startedAt}` | Status must be `ready`. The host starts immediately; a guest marks itself ready and the match starts automatically once every player has. Running → `startedAt = server now`, 60 min to finish. |
| `reportProgress` | `{matchId, progress 0..1}` | `{matchId, progress}` | Running matches only; at most once per second per player (`resource-exhausted`), stored in `players.{uid}.progress` / `lastProgressAt`. |
| `finishMatch` | `{matchId, elapsedMs, hintsUsed, solutionHash?}` | `{matchId, status, elapsedMs, result, opponentFinished, player}` | Server elapsed = `now − startedAt` and is what gets stored. Rejected (`failed-precondition`) when `elapsedMs < 0.7 × serverElapsed − 5 s`, or when the match has a `solutionHash` and the client's differs (missing → `invalid-argument`). The first valid finisher wins; the match closes when both finish (identical server times draw), when the other player forfeits, or 15 minutes after the first finish (`expireMatches`). Re-reporting after finishing returns the stored outcome and changes nothing. |
| `leaveMatch` | `{matchId}` | `{matchId, status, result}` | Before the start → `cancelled` (invite code released). While running → the leaver `forfeit`s and the opponent `win`s (settled immediately). After finishing or on a closed match → no-op. |
| `cancelMatch` | `{matchId}` | `{matchId, status, result}` | Host only, before the start. Running → `failed-precondition` (use `leaveMatch`). |

`expireMatches` (every minute) closes matches with `expiresAt ≤ now`:
lobbies (`waiting`/`ready`) are cancelled; a running match with one finisher is a
win by `forfeit` for the finisher; a running match nobody finished within 60
minutes is a `draw` for both (no trophies, no rewards). It also deletes
matchmaking entries older than 10 minutes. Random matches get their puzzle from
`matchPool/{lang}_{level}` = `{puzzles: [{puzzleId, letterCells, solutionHash?}]}`,
which the publisher fills (admin-only collection); without a pool the dailies
of the language are used.

### Trophies

`users/{uid}.trophies` starts at 0 and never drops below 0 (server-only field).
With `E = 1 / (1 + 10^((opponent − me) / 400))` (Elo expectation) and the Elo
swing `K·scale = 32 × 1.25 = 40`:

- win: `30 + 40·(0.5 − E)`, clamped to **[+10, +50]** — beating a much stronger player pays +50, a much weaker one +10;
- loss (and forfeit): `−(15 + 40·(E − 0.5))`, clamped to **[−25, −5]** — the favourite loses up to 25, the underdog as little as 5;
- draw: 0.

`src/lib/trophies.ts` is the pure implementation (`trophyDelta`, `winDelta`,
`lossDelta`, `applyTrophyDelta`). Every settlement writes
`trophyBoard/{lang}/entries/{uid}` = `{uid, trophies, displayName, updatedAt}`
(public read). `trophyLeaderboard({lang, limit≤100 (default 50)})` returns
`{lang, entries: [{uid, displayName, trophies, updatedAt, rank}], me}`; `me`
is the caller's entry with an **exact** rank computed by a count aggregation of
entries with more trophies (one aggregation read per call), or `null` before the
caller's first match. We chose the count query over a scheduled `rankTrophies`
job because the `Db` abstraction already had `countDocs`; no stored rank exists.

### Rewards on match results

Applied in the settlement transaction, once per `(match, player)` through the
ledger entry `users/{uid}/ledger/match_{matchId}_{uid}` (`type: earn_match`,
`server.source: 'server'`; `earn_match` and `earn_coop` are server-only types
and rejected by `syncLedger` and the rules):

| Result | Coins | Season points | XP |
|--------|-------|---------------|----|
| win | +40 | +25 | +60 |
| loss | +10 | +5 | +20 |
| forfeit / draw | 0 | 0 | 0 |

Coins, points and XP go only to players who actually **finished** the puzzle
(a forfeit win still moves trophies, but pays nothing — otherwise two accounts
could farm coins by forfeiting). At most **10 rewarded matches per player per
UTC day** (`users/{uid}/claims/earn_match~day~{date}`); beyond that the entry is
stored as `rejected` (so replays stay idempotent) and only trophies move. XP
accumulates in `users/{uid}.xp`, season points in
`users/{uid}.season.{seasonId}.points`; the outcome is mirrored into
`players.{uid}.rewards` and `players.{uid}.trophyDelta` on the match document
for the result screen.

### Seasons

Seasons are consecutive **42-day** windows in UTC; **season 1 starts Monday
2026-11-02**. Id = `${year of the season's first day}-S${n}` with `n` the
global 1-based season number: `2026-S1` (2026-11-02 … 2026-12-13), `2026-S2`
(2026-12-14 … 2027-01-24), `2027-S3` (2027-01-25 … 2027-03-07), … — the year
prefix groups and sorts, `n` never resets. Dates before 2026-11-02 have no
season and earn no season points. `src/lib/season.ts`: `seasonIdFor('YYYY-MM-DD')`,
`seasonIdAt(ms)`, `seasonBounds('2026-S1' | n)` → `{id, n, start, end (inclusive), startMs, endMs (exclusive)}`,
`seasonBoundsFor(date)`. `packages/core` mirrors the same rule.

### Co-op rooms

Up to four players fill one grid together. `coopRooms/{roomId}` (shape:
`schema/coop-room.schema.json`) is readable by its members; each member may
update only its own `members.{uid}.cursor` (letter-cell index or null) and
`members.{uid}.lastSeenAt` (heartbeat). Grid cells are written directly by
members to `coopRooms/{roomId}/cells/{cellIndex}` = `{symbol: 0..31 | null, by: <own uid>, at: ms}`
(numeric `cellIndex`, exactly those three fields, no deletes); clients listen
to the `cells` collection and the room document.

| Callable | Input | Output | Rules |
|----------|-------|--------|-------|
| `createCoopRoom` | `{lang, puzzleId}` | `{roomId, code, room}` | Any puzzle id; `letterCells`/`solutionHash` are filled when the puzzle is known (pool / dailies / `puzzleIndex`), else `null`. Host gets colour 0; status `open`; code valid 24 h. |
| `joinCoopRoom` | `{code}` | `{roomId, room}` | ≤ 4 members (5th → `failed-precondition`), lowest free colour 0..3, allowed while `open` or `running`; re-joining is a no-op. |
| `startCoopRoom` | `{roomId}` | `{roomId, room}` | Host only: `open` → `running`, `startedAt`. (Not in the original brief; added so the app can distinguish lobby from play without writing `status` itself.) |
| `leaveCoopRoom` | `{roomId}` | `{roomId, status, hostUid}` | Removes the member; the earliest-joined remaining member inherits the host role; an emptied room is closed (`finished`, `finishReason: 'abandoned'`, code released). |
| `finishCoopRoom` | `{roomId, solutionHash?}` | `{roomId, status, rewarded, members: {uid: rewards}}` | Host confirms completion; when the room knows a `solutionHash` the client must send the matching one. Every current member gets **+25 coins and +30 XP** once (`users/{uid}/ledger/coop_{roomId}_{uid}`, `type: earn_coop`), capped at **5 rewarded rooms per player per UTC day**; rooms with a single member or younger than 60 s pay nothing (anti-farming). Calling again returns the stored outcome. |

`expireRooms` (every 15 min) closes `open`/`running` rooms whose last activity
(function writes or any member's `lastSeenAt`) is older than 2 hours
(`finishReason: 'expired'`) and releases their codes.

### Client-side ledger types added

`earn_season` (season-pass tier claim, ≤ 500 coins, once per `refId` such as
`2026-S1:3`) and `earn_mission` (≤ 100 coins, once per mission ref, ≤ 10 per
day) are accepted from clients by `syncLedger` and the rules, so the pass and
mission UIs can pay out through the normal ledger sync.
