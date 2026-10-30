# Production setup guide

Everything in this repository runs offline out of the box: the app plays bundled puzzles with a local
coin wallet and all cloud features disabled. To ship, create the accounts below and fill in the
configuration. Nothing secret is committed.

## 1. Accounts
| Service | Why | Where it is configured |
|---------|-----|------------------------|
| Apple Developer Program | iOS distribution, Sign in with Apple, StoreKit products | `apps/mobile/ios` (bundle id `com.chetz.app`), App Store Connect |
| Google Play Console | Android distribution, Play Billing products | `apps/mobile/android` (application id `com.chetz.app`) |
| Firebase project | Auth, Firestore, Functions, Remote Config, Storage/Hosting (CDN for puzzles) | `firebase/`, `functions/`, `apps/mobile` (google-services files) |
| RevenueCat | Purchases and entitlements across both stores | `functions` secret `REVENUECAT_WEBHOOK_SECRET`, app config `revenueCatApiKey` |
| AdMob | Rewarded and interstitial ads, UMP consent | app config ad unit ids |
| PostHog, Sentry (optional at launch) | Product analytics, crash reporting | app config DSN/keys |

## 2. Firebase
1. `firebase projects:create chetz-prod` (or use the console), enable Authentication (Anonymous, Apple, Google), Firestore (production mode), Storage, Remote Config, App Check.
2. Download `google-services.json` to `apps/mobile/android/app/` and `GoogleService-Info.plist` to `apps/mobile/ios/Runner/`. They are git-ignored.
3. Deploy rules, indexes and functions: `cd functions && npm ci && npm run build && cd ../firebase && firebase deploy --only firestore,storage,functions,remoteconfig` (copy `firebase/.firebaserc.example` to `.firebaserc` first). The `hosting` target `chetz-admin` expects the Phase-2 admin web app at `apps/admin/build/web`; until it exists, deploy without `hosting` and use the editorial gallery (`chetz_gen gallery`) plus the publish script below.
4. Set secrets: `firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET` and `DAILY_SEED_SECRET` (the HMAC key used by `tools/generate dailies`; keep it out of git).
5. Give your editor account the admin claim (one-off script with the Admin SDK: `admin.auth().setCustomUserClaims(uid, {admin: true})`).

## 2b. Sign-in, usernames, feedback and ratings
Players start as anonymous Firebase users. Signing in with Google (Android) or Apple (iOS) *links* that
account, so the uid, progress and coins stay; the player then picks a unique username (`claimUsername`
callable, `usernames/{key}`). Without Firebase the account card and sign-in button are hidden.
1. **Google**: Authentication → Sign-in method → enable Google. Add the Android app's SHA-1 and SHA-256
   (`cd apps/mobile/android && ./gradlew signingReport`, debug and release keys, plus the Play App Signing key
   from the Play Console) in Project settings → Your apps, then download `google-services.json` again so it
   carries the OAuth web client (`default_web_client_id`). `--dart-define=CHETZ_GOOGLE_CLIENT_ID=<web client id>`
   overrides it.
2. **Apple**: enable the Apple provider (Services ID, Team ID, key) and add the *Sign in with Apple* capability
   to the Runner target in Xcode. App Store guideline 4.8 requires it once Google sign-in is offered on iOS.
3. **Feedback** (Settings → feedback, puzzle menu → report a clue) lands in Firestore `feedback/{id}` with
   `status: "new"`; only admins can read it. Reports wait on the device while offline.
4. **Rating prompt**: the stores' own review dialog after 5 completed puzzles (≥ 2 days after install, every
   120 days at most, 3 times in total). The Settings "Rate" link needs `--dart-define=CHETZ_APP_STORE_ID=<id>`
   on iOS.

## 3. Puzzle content and CDN
```
export PATH=/path/to/flutter/bin:$PATH
dart run tools/generate/bin/chetz_gen.dart --content content templates --lang he --count 40
dart run tools/generate/bin/chetz_gen.dart --content content pack --lang he --level 1 --pack 1
DAILY_SEED_SECRET=... dart run tools/generate/bin/chetz_gen.dart --content content dailies --lang he --from 2026-11-01 --days 90
dart run tools/generate/bin/chetz_gen.dart --content content manifest --lang he
dart run tools/generate/bin/chetz_gen.dart --content content validate --lang he
```
**One command:** `tools/seed_firebase.sh --key /path/sa.json [--project arrowword-270f5] [--bank]` deploys the
rules, makes the bucket publicly readable, converts the content to the compact format 2, builds the
manifests, validates, publishes every puzzle and (with `--bank`) loads the clue and word banks into the
admin-only `clues/` and `words/` collections. It prints the `CHETZ_CDN` value for the app. Puzzle files use
format 2 (`clues` arrays instead of `clueCells`/`words` objects, ~4× smaller); the app reads both formats.

The steps it runs, for reference: publish to Firebase (Storage + Firestore) with the script that reuses the `publishPuzzle` /
`rebuildManifests` handlers, so the CDN files and documents are exactly what the functions produce:
```
cd functions && npm run build
GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json GCLOUD_PROJECT=chetz-prod STORAGE_BUCKET=chetz-prod.appspot.com \
  node scripts/publish-content.cjs --content ../content --lang he          # add --lang en for English
```
Puzzle files land at `puzzles/{lang}/...v{n}.json` (immutable cache), manifests at `manifests/{lang}/daily.json`
and `packs.json` (5-minute cache); `dailies/*` documents carry the `solutionHash` and `letterCells` used
by the leaderboard validation. The daily manifest only exposes dates up to three days ahead. Point the
app at the bucket or a CDN in front of it with `AppConfig.cdnBaseUrl`. The same script was verified
against the Firebase emulators (`firebase emulators:exec --only firestore,storage`).

Content credit: clue/answer pairs were seeded from the public Mordo clue dictionary
(pitaronfree.blogspot.com). Every imported clue has `status: imported`; the admin review flow upgrades
clues to `approved`. Review the licensing position of imported clues with counsel before launch; our
recommendation in docs/GAME_PLAN.md is to treat them as drafts and ship editor-approved clues.

## 3b. Picture clues (free images)
Image-generation services (OpenAI, Google, Stability) refuse to draw real public figures, and likeness/publicity
rights make generated celebrity images legally risky, so famous people are illustrated with **freely licensed
photos from Wikimedia Commons**, found through Wikidata:
```
python3 -I tools/content/fetch_images.py --lang he --words content/he/lexicon/words.jsonl.gz --out content/he --only-proper --limit 500
python3 -I tools/content/fetch_images.py --lang en --words content/en/lexicon/words.jsonl.gz --out content/en --limit 500
dart run tools/generate/bin/chetz_gen.dart --content content pack --lang he --level 3 --pack 4 --pictures 0.3 --title-he "חבילת תמונות" --title-en "Picture Pack"
# Level 3 or higher: most pictured subjects are proper nouns and multi-word names, which levels 1–2 exclude.
# The filler seeds up to two picture words per puzzle before the normal fill, so a 30-puzzle pack needs ≥ 60 pictured words.
```
Only PD / CC0 / CC BY / CC BY-SA files are kept; credit, licence and source URL travel with each puzzle and are
shown in the app's image-credits screen (CC BY-SA requires that attribution). Run the fetcher from a normal
network (Wikimedia rate-limits shared cloud proxies). AI-generated pictures are fine for generic nouns
(animals, objects) if you want them later: add records to `images.jsonl` with `license: "generated"`.

## 3c. Multiplayer
The publish script also writes `matchPool/{lang}_{level}` documents (pack puzzles with their solution hashes) that random
matchmaking draws from. Matches, matchmaking queues, trophy boards and co-op rooms live in Firestore and are driven by the
callables documented in `functions/README.md` ("Multiplayer"); the scheduled jobs `expireMatches` (every minute) and
`expireRooms` (every 15 minutes) need Cloud Scheduler, which `firebase deploy` sets up. Keep App Check enabled in production
so only the app can call them.

## 4. RevenueCat and store products
Create these products in both stores and in RevenueCat (identifiers must match `functions/src/economy.ts`
and the app's `StoreService`): consumables `coins_300`, `coins_800`, `coins_2000`, `coins_6000`;
non-consumable `remove_ads`; subscriptions `premium_monthly`, `premium_yearly` with a 7-day trial;
one-time offer `starter_pack`. Entitlements: `premium`, `remove_ads`. Add the RevenueCat webhook URL
(the deployed `revenuecatWebhook` function) with the bearer secret from step 2.4.

## 5. AdMob
Create the app in AdMob, two rewarded units (`earn_coins`, `free_letter`) and one interstitial
(`after_completion`), enable the UMP consent message for EEA/UK, and put the ids in `AppConfig`. Keep
`adsEnabled=false` in debug builds (test ids are used automatically there).

## 6. Store listings
Hebrew and English listings, screenshots and privacy policy URL (both languages); App Privacy / Data
Safety declarations listing the ads SDK; ATT prompt text in `Info.plist`; age rating 4+/Everyone with
"contains ads" and "in-app purchases"; the subscription screen already shows price, period, auto-renew
text and the terms/privacy links required by Apple and Google.

## 7. Release
```
cd apps/mobile
flutter build appbundle --release   # Android (sign with your upload key in android/key.properties)
flutter build ipa --release         # iOS, on a Mac with Xcode
```
CI builds run on every push (`.github/workflows`). Tag releases `v1.0.0`; the changelog lives in the PR history.
