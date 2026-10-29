# Chetz (חֵץ) — Hebrew + English arrowword game

Arrowword (תשחץ) puzzles for iOS and Android: packs by difficulty, two generated dailies per language, a coin economy for hints, fair ads and an accessible solving experience. The plan behind every decision is in [docs/GAME_PLAN.md](docs/GAME_PLAN.md).

## Repository map

| Path | What it is | Verify with |
|------|------------|-------------|
| `packages/core` | Dart: puzzle model + JSON codec, language profiles (he/en), solving engine (navigation, checking, hints, final-letter display), generator (layout templates, CSP fill, clue assignment, difficulty, validation), SVG preview | `dart analyze && dart test` |
| `tools/generate` | CLI `chetz_gen`: `templates`, `pack`, `dailies`, `manifest`, `validate`, `preview`, `gallery`, `stats` | `dart analyze && dart run bin/chetz_gen.dart --help` |
| `tools/content` | Python: scrape the Mordo clue dictionary, build the Hebrew lexicon + clue DB, build the English lexicon (ENABLE + WordNet), fetch freely licensed pictures (Wikidata + Commons) | `python3 -I tools/content/build_he_content.py RAW OUT`, `fetch_images.py --lang he ...` |
| `content/he` | Lexicon (74k words), clues (257k pairs), 40 templates per level, generated packs and 95 days of dailies, manifests | `dart run tools/generate/bin/chetz_gen.dart --content content validate` |
| `apps/mobile` | Flutter app (Riverpod, go_router, custom grid painter, custom keyboards, wallet, packs, dailies, settings, onboarding, he/en UI) | `flutter analyze && flutter test` |
| `functions` | Firebase Functions (TypeScript): RevenueCat webhook, ledger validation, daily leaderboard submission, publishing, manifests, account deletion | `npm ci && npm run build && npm test` |
| `schema` | JSON Schema contract between Dart and TypeScript (puzzle, progress, ledger, manifests) + fixtures | `node schema/validate.mjs` |
| `firebase` | Firestore/Storage rules, indexes, Remote Config defaults, `firebase.json` | `firebase deploy --only firestore,storage` |
| `docs` | Game plan, brand shortlist, production setup guide | — |

## Quick start
```bash
export PATH=/path/to/flutter/bin:$PATH          # Flutter 3.47+, Dart 3.13+
(cd packages/core && dart pub get && dart test)  # engine + generator tests
(cd tools/generate && dart pub get)
dart run tools/generate/bin/chetz_gen.dart --content content stats --lang he
dart run tools/generate/bin/chetz_gen.dart --content content gallery --lang he --out build/gallery   # browse puzzles
(cd apps/mobile && flutter pub get && ../../tools/sync_assets.sh && flutter run)
```

## Feature map (what exists today)
- **Play**: packs by level with a star-based progression gate, two dailies per language with streaks and archive, three play modes (relaxed / normal / newspaper), hints with coin prices, the **A→Z letter cycler** for the last empty letter of a word, undo, pencil marks, Hebrew final-letter display, geresh key.
- **Meta**: 32 achievements, 3 daily + 3 weekly missions (deterministic, coin rewards), lifetime stats, profile with avatar and rank, themes (light/dark/system/high-contrast/custom colours).
- **Picture clues**: `ClueSlot.image` renders a freely licensed photo (Wikimedia Commons via Wikidata, licence and credit recorded) instead of text; generated with `chetz_gen pack --pictures 0.3`.
- **Content**: Hebrew 580 + English ~400 puzzles, 2 tutorial puzzles per language, 95 days of dailies per language.
- **Backend**: ledger validation, purchases webhook, leaderboard submission, publishing, manifests; CI for every package.

## How a puzzle is made
1. **Lexicon**: `tools/content` turns the clue dictionary into `words.jsonl.gz` (normalised Hebrew symbols: 22 letters + 5 geresh letters, final letters folded) and `clues.jsonl.gz`, with a difficulty per word from how often crossword setters use it.
2. **Templates**: `chetz_gen templates` anneals grid shapes that satisfy the arrowword rules (every run of letters is exactly one clued word, each clue cell serves one or two words with the right arrow exits, grid connected, checked-letter ratio and word-length mix per level).
3. **Fill**: a bitset constraint solver places words most-constrained-slot first, steering toward the level's difficulty band; restarts are seeded, so a puzzle is reproducible from its seed.
4. **Clues**: for every word the assigner picks an approved clue that fits the cell geometry (a fit model with per-glyph widths), is in the level's difficulty band, is not reused inside the pack or within 120 days of dailies, and never spells out an answer of the grid.
5. **Validate + score**: structural rules, dictionary membership, uniqueness, fit, checksum; a logistic difficulty score places the puzzle in its band.
6. **Publish**: `manifest` writes the CDN manifests; the app verifies checksums; `functions/publishPuzzle` registers dailies for leaderboards.

Dailies are seeded with `HMAC(secret, lang|date|variant)` so nobody can pre-compute them without the secret.

## Status
See the pull request description for what is wired versus stubbed. Production setup (accounts, keys, store products) is in [docs/SETUP.md](docs/SETUP.md); naming in [docs/BRAND.md](docs/BRAND.md); content provenance in [content/LICENSES.md](content/LICENSES.md).
