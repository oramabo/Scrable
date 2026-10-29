# חץ / Chetz — mobile app

Flutter app for the Hebrew + English arrowword game. Engine and puzzle model come
from `packages/core` (`chetz_core`); this app only renders, persists and monetises.

## Run

```sh
export PATH=/opt/flutter/bin:$PATH
# 1. bundle puzzle content (from the monorepo root; idempotent)
tools/sync_assets.sh --lang he --days 15
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
| `CHETZ_FIREBASE=true`      | Anonymous auth, progress/ledger sync, Remote Config (needs google-services.json / GoogleService-Info.plist) |
| `CHETZ_CDN=https://…/`     | Fetch manifests/puzzles not bundled in the app             |

## Verify

```sh
flutter analyze
flutter test
flutter build apk --debug
```

## Layout

- `lib/core` — config (`AppConfig`, `GameConfig`), content loading (bundled → CDN, checksum-verified),
  JSON file storage, theme, l10n helpers, router, analytics.
- `lib/features/puzzle` — solving screen: `PuzzleController` (Riverpod `AsyncNotifier` over the
  `chetz_core` navigator/checker), `GridPainter` + `PuzzleGrid` (InteractiveViewer, semantics overlay),
  clue bar, custom keyboard, hint/completion sheets.
- `lib/features/{packs,daily,wallet,store,ads,sync,settings,onboarding,stats,home}` — one folder per feature.
- `assets/puzzles/<lang>` — written by `tools/sync_assets.sh`; `index.json` maps ids to asset paths.
