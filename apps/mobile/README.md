# חץ / Chetz — mobile app

Flutter app for the Hebrew + English arrowword game. Engine, puzzle model and the
meta layer (events, stats, achievements, missions) come from `packages/core`
(`chetz_core`); this app renders, persists and monetises. Design brief: `docs/UX.md`.

## Run

```sh
export PATH=/opt/flutter/bin:$PATH
# 1. bundle puzzle content (from the monorepo root; idempotent)
tools/sync_assets.sh --lang he --days 15      # packs, dailies, tutorial, images, manifests
tools/sync_assets.sh --lang en --days 15
# 2. run
cd apps/mobile
flutter pub get          # also runs flutter gen-l10n (lib/l10n/generated)
flutter run
```

Everything runs offline by default. Integrations are compile-time flags:

| `--dart-define`            | Effect                                                     |
|----------------------------|------------------------------------------------------------|
| `CHETZ_ADS=true`           | Google Mobile Ads + UMP consent (needs real app/unit ids)  |
| `CHETZ_IAP=true` + `CHETZ_REVENUECAT_KEY=…` | RevenueCat store                          |
| `CHETZ_FIREBASE=true`      | Anonymous auth, progress/ledger/profile sync, Remote Config, hard-daily leaderboard (needs google-services.json / GoogleService-Info.plist) |
| `CHETZ_CDN=https://…/`     | Fetch manifests, puzzles and picture-clue images not bundled in the app |

## Verify

```sh
flutter analyze
flutter test                      # unit + widget tests; also writes UI review PNGs
ls test/screenshots/goldens/      # home / solving / completion / achievements / profile / theme picker, light + dark
flutter build apk --debug
```

The screenshot tests (`test/screenshots/`) load the real fonts and write
390×844 PNGs on every run; they never fail on pixel differences.

## Layout

- `lib/core` — config (`AppConfig`, `GameConfig`), content loading (bundled → cache → CDN,
  checksum-verified, picture-clue image store), JSON file storage, theme tokens (UX §2) incl.
  custom palettes, l10n helpers, router (4 tabs: Play · Daily · Together · Me), analytics.
- `lib/features/puzzle` — solving screen: `PuzzleController` (Riverpod `AsyncNotifier` over the
  `chetz_core` navigator/checker), `GridPainter` + `PuzzleGrid` (InteractiveViewer, semantics
  overlay, teal word wash, wrong-word shake, completion flip, picture clues), clue bar, custom
  keyboard + A→Z cycler, hint/completion sheets.
- `lib/features/meta` — `GameEventsController` (events → `PlayerStats`, mission counters,
  achievement credits), missions strip/section, achievements screen, image credits.
- `lib/features/{packs,daily,wallet,store,ads,sync,settings,onboarding,profile,leaderboard,together,stats,home}`.
- `assets/puzzles/<lang>` — written by `tools/sync_assets.sh`; `index.json` maps ids to asset paths.
