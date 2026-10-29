# Brand name

The product needs a name that is **not** the generic category word (תשחץ / arrowword), works in Hebrew and
English storefronts, is short enough for an app icon, and is unlikely to collide with existing apps.
The codebase uses the working name **Chetz** (חֵץ, "arrow") everywhere a name is needed: Dart packages
(`chetz_core`, `chetz_gen`, `chetz_app`), the bundle id `com.chetz.app`, and the UI strings
`app_name` in `apps/mobile/lib/l10n/*.arb`. Renaming is a search-and-replace plus new store listings.

## Shortlist

| Name | Hebrew | Why it works | Watch out |
|------|--------|--------------|-----------|
| **Chetz** (recommended) | חֵץ | One syllable, means "arrow" — the defining feature of the puzzle; reads as a brand in both scripts; store subtitle carries the category ("חץ – תשחצים ותשבצים", "Chetz – Arrowword Puzzles"). | English speakers may say "chets"; that is fine, but the ch sound needs the logo to carry the arrow idea. |
| Chetzi | חִצִּי | Friendlier, playful diminutive of the same word. | Slightly longer; same pronunciation issue. |
| Tashi | טאשי | Short for תשחץ, easy in English, positive associations. | Weak in Hebrew (looks foreign). |
| Milon Chetz | מילון חץ | "Arrow dictionary", signals the huge clue dictionary behind the game. | Two words; dictionary may sound like a tool, not a game. |
| Arrowly | ארולי | Descriptive English brand with a soft ending; good for US/UK ASO. | Means nothing in Hebrew; would need a second Hebrew brand. |

## Before launch
1. Search both stores for the chosen name and its Hebrew spelling.
2. Trademark search in Israel (ILPO) and, for the English launch, USPTO/UKIPO classes 9 and 41.
3. Register the `.app`/`.co.il` domains for the support URL required by the stores.
4. Keep the category words in the subtitle/keywords: תשחץ, תשבץ, תשחצים, arrowword, crossword.
