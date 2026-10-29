# chetz_core

Pure Dart package shared by the Chetz app, the content CLI and the admin tool.

| Area | Entry points |
|------|--------------|
| Language layer | `LanguageProfile`, `HebrewProfile` (27 symbols: 22 letters + ג׳ ז׳ צ׳ ת׳ ד׳; final letters fold to base), `EnglishProfile` (A–Z), `Languages.byCode` |
| Model | `Puzzle`, `GridShape`, `Pos`, `Dir`, `Arrow` (A, D, DA, AD, UA, BD), `ClueCell`/`ClueSlot`, `PuzzleWord`, `PuzzleDifficulty`, `PuzzleMeta`, `WordIndex` |
| Codec | `PuzzleCodec` (JSON, `xor1` solution obfuscation, canonical checksum, `solutionHash`) |
| Engine | `PuzzleProgress` (saved state + `merge`), `PuzzleNavigator` (selection rules), `PuzzleChecker` (type/clear/evaluate/reveal/check/stars), `FinalLetterPolicy` ("across wins") |
| Generator (`package:chetz_core/generator.dart`) | `Lexicon`, `DictionaryIndex`, `LevelConfig`, `LayoutValidator`, `LayoutGenerator`, `Filler`, `ClueAssigner`, `FitModel`, `DifficultyModel`, `PuzzleValidator`, `PuzzleBuilder`, `Seeds`, `SvgPreview` |

Coordinates: column 0 is the first column in the language's reading direction (rightmost in Hebrew,
leftmost in English). Arrows describe where the first letter sits relative to the clue cell and which
way the word runs, so the generator never reasons about left/right; only renderers flip.

```bash
dart pub get
dart analyze
dart test            # includes an end-to-end generation test when ../../content/he exists
```
