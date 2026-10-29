# chetz_gen

```bash
export PATH=/path/to/flutter/bin:$PATH
dart pub get
dart run bin/chetz_gen.dart --content ../../content <command> --lang he|en
```

| Command | Purpose |
|---------|---------|
| `templates --level N --count 40` | Anneal valid layout templates into `content/<lang>/templates/L<N>.json` |
| `pack --level N --pack M [--count 30]` | Generate a pack; words and clues are not repeated inside the pack; difficulty ramps across the pack |
| `dailies --from YYYY-MM-DD --days 90 [--secret ...]` | Generate easy + hard dailies seeded with `HMAC(secret, lang|date|variant)`; recent words excluded |
| `manifest` | Write `daily.json`, `packs.json` and `publish-index.json` (solution hashes for the leaderboard) |
| `validate` | Re-validate every puzzle against the lexicon, layout rules and checksums |
| `preview --in puzzle.json --out puzzle.svg` | SVG rendering with solution |
| `gallery --out build/gallery [--filter he-l1-p01]` | HTML review gallery for editors |
| `stats` | Lexicon size and eligible words per level |
| `word_info.dart <canonical...>` | Debug a word's clues and whether they fit full/half cells |

Generation is deterministic: the same seed, template library, dictionary snapshot and generator version
reproduce the same puzzle. Change `--salt` (packs) or the secret (dailies) to get different puzzles.
