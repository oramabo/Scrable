# תשחץ / Arrowword — Game Plan A→Z (Hebrew + English arrowword for iOS + Android)

## Context

You want to build and sell a **תשחץ** (arrowword / Swedish-style crossword: clues live inside shaded grid cells with arrows pointing at the answers) for iOS and Android, in **Hebrew and English**, with:
- puzzle **packs by difficulty, 30 puzzles each** (you chose: packs unlock **free by progression**; money comes from coins, ads and a Premium subscription);
- **two algorithmically generated daily puzzles** per language (easy + super hard);
- a **coin economy** for hints (letter / word) with **ads** as an alternative way to earn;
- a plan "from A to Z" plus smart, simple, fun feature ideas;
- **English support**: English UI and English-language puzzles on the same engine.

The repository `/home/user/Scrable` is empty, so this plan defines the product, the content pipeline, the puzzle generator, the architecture, the monetisation and the delivery roadmap from scratch. You chose **plan only for now**; §12 lists the first build steps for when you say go.

## Execution status

Built and pushed on branch `docs/game-plan` (PR #1): core engine + generator (49 tests; layouts have no blank squares, every clue cell carries one or two clues), content CLI, Hebrew and English content (1,014 validated puzzles incl. a Hebrew picture pack, tutorials, word banks, on-device lexicons, 131 Commons pictures), Firebase backend incl. multiplayer (68 tests, rules smoke-tested on the emulator), JSON schema contract, CI, Flutter app (152 tests, screenshot tests, debug APK) with solving, packs, dailies, random puzzles, achievements, missions, profiles and themes, season pass and XP, versus and co-op screens, notifications. English pictures still need a fetcher run from a normal network (Wikimedia rate-limits this environment). Manual production steps (accounts, keys, store listings, legal review of imported clues) are in docs/SETUP.md.

### What the research found (and how it shaped the plan)
- **Hebrew competitors**: "התשחץ שלי" (PineApps) is the incumbent: ~1,000 puzzles, daily + leaderboard, head-to-head, 4.6★ from ~12k ratings. Prices: gold subscription ₪9.90/mo · ₪19.90/qtr · ₪59.90/yr; coins 100/₪4.90 → 3000/₪39.90; remove ads ₪24.90; challenge pack ₪24.90. Top complaints: **heavy ads, battery drain, dated UI**. "תשחץ יומי" (KitApp, Oct 2026) is new (3.4★), bundles mini word games, has a "newspaper mode" (no auto-check) and VoiceOver support. Neither has generated dailies at two levels, a modern UX, or serious accessibility.
- **English competitors**: the mobile arrowword niche is a handful of paid or dated apps (Crosswords Plus, PuzzleLife, "Crossword Daily - Arrow Word") and one multi-language free-to-play title; generic crossword apps are giants. "Arrowword" is the searchable term.
- **Word data licences**: Hspell's Hebrew word lists are **AGPL** (closed-source use needs a separate arrangement) → build our own lexicon, use Hspell only as an internal spell-check oracle. English: **ENABLE** is public domain, **SCOWL** is permissive, `wordfreq` data is CC BY-SA (internal use only). Never scrape published crossword clues.
- **No open arrowword generator exists** (only standard crossword fillers; MotsFlex is an MIT arrowword *editor*). The layout + fill algorithm in §5.3 is a core asset we build.

---

## 1. Decisions (rows 1, 7, 10, 11, 12 confirmed by you; the rest are recommendations the plan assumes)

| # | Decision | Recommendation | Why / alternative |
|---|----------|----------------|-------------------|
| 1 | App framework | **Flutter** (one Dart codebase) — confirmed | Pixel-perfect custom grid, excellent RTL, mature IAP/ads plugins, small team. |
| 2 | Generator language | **Dart package shared with the app** (`packages/core`) | One implementation of the puzzle model, normalisers, validator and fit model for pipeline, admin and app (no TS/Dart drift on final letters or geresh); enables an on-device "endless practice" mode later. Firebase Functions stay TypeScript; the contract between them is a versioned **JSON Schema file** plus shared normalisation fixtures that both sides test against. Alt: TypeScript generator sharing a zod schema with Functions. Corpus/LLM scripts stay Python. |
| 3 | Backend | **Firebase** (Auth, Firestore, Functions, Remote Config, Messaging, App Check) + CDN for puzzle JSON | Fastest path, free tier covers beta. Alt: Supabase. |
| 4 | Payments | **RevenueCat** (`purchases_flutter`) | One SDK for both stores, receipt validation, entitlements, webhooks, price experiments. |
| 5 | Ads | **AdMob** (`google_mobile_ads`), rewarded-first, server-side verification; mediation (e.g. LevelPlay) later | Rewarded ads are player-chosen → good UX, highest eCPM. |
| 6 | Analytics / crashes | **PostHog** + **Sentry** | Both already in your toolset. |
| 7 | Content authoring | **Own lexicon + LLM-drafted clues + human crossword editor approval** — confirmed (no existing content) | Clue quality is the product; LLM gives volume, editor gives trust. |
| 8 | Markets | Israel first, then US/UK/CA/AU with English content | Store listings in both languages. |
| 9 | Brand name | Needs a distinctive name; "תשחץ" alone is the generic category already in competitor titles | Keep "תשחץ" / "Arrowword" in subtitle and keywords. Candidates to check: "חֵץ", "תשחץ+", "תשחצון". |
| 10 | Pack unlock model | **Progression unlocks packs for free** (stars in pack N open pack N+1); Premium skips the gate — confirmed | Monetise hints, ads and Premium only. Thresholds in Remote Config. |
| 11 | Scope right now | **Plan only** — confirmed | No code until you say go. |
| 12 | Languages | **Language-agnostic engine from day one; Hebrew puzzles + English UI at MVP; English puzzles + global launch in Phase 2** | The language layer is cheap now and expensive to retrofit; English content needs its own lexicon, clue DB and editor, so it ships once the Hebrew pipeline is proven. Alt: both at MVP with two editors from day one. |

---

## 2. Product vision & positioning

**One line**: the cleanest, fairest arrowword on mobile, in Hebrew and English: two fresh dailies per language every day, packs for every level, hints that help instead of punish, ads only when *you* ask for them, fully accessible (large text, screen reader, high contrast).

**Audience**: Hebrew: core 35–70 (crossword lovers, newspaper habit), secondary commuters 25–35 (streak crowd), tertiary learners/diaspora. English: UK/US/AU arrowword and crossword fans, plus Israelis practising English.

**Differentiators** (each maps to a feature below):
1. Generated dailies at **two levels** with streaks, archive, leaderboard and spoiler-free share card.
2. **Readable on a phone**: tap any cell → big clue bar; pinch-zoom with cells never below 44 dp; auto-pan; custom keyboard with large keys.
3. **Fair monetisation**: rewarded ads only, strict interstitial caps, no banner on the puzzle screen (the incumbent's #1 complaint).
4. **Smart hints**: easier alternative clue, "smart letter" (unlocks most crossings), "ask a friend" via WhatsApp (viral + free).
5. **Accessibility as a feature**: seniors preset, VoiceOver/TalkBack, dynamic type, colour-blind-safe error marks.
6. **Self-calibrating difficulty**: telemetry re-rates every clue so "easy" really is easy.
7. **Two languages, one engine**: Hebrew (RTL) and English (LTR) puzzles from one generator; UI language and puzzle language chosen independently; bilingual puzzles later.

---

## 3. Game design

### 3.1 Core solving experience
Screen anatomy (portrait):
- **Top bar**: back, title/level, timer (hidden by default), coins, hint button.
- **Grid** (CustomPainter inside `InteractiveViewer`): clue cells shaded with small clue text + arrow glyph; letter cells white; active word highlighted, active cell stronger; pencil letters grey. Auto-zoom keeps cells ≥ 44 dp; a zoom button mirrors pinch.
- **Clue bar** (above keyboard): active clue in large type, direction icon, pattern `_ _ א _`, big ‹ › buttons for previous/next word; if the cell has two words, both clues show with the active one bold; tap to switch. Every gesture has a button equivalent.
- **Custom keyboard**: follows the puzzle language. Hebrew: 22 letters in alphabetical rows (setting: standard Israeli layout; final-form keys exist for familiarity but emit the base letter), geresh key. English: QWERTY (setting: ABC). Plus backspace, next word, hint. Keys ≥ 48 dp, press-preview popup, "large keyboard" mode. Hardware keyboards supported, never required.

Input model:
- Tap letter cell → select; if it belongs to two words, tapping the cursor cell toggles direction, otherwise the current direction is kept when possible, else across.
- Tap clue cell → large popover listing its 1–2 clues with arrow glyphs; choosing one jumps to that word's first empty cell.
- Typing fills and advances, skipping filled cells (setting, default on); at word end jumps to the next incomplete word (setting, default on). Backspace clears the cursor cell, or moves back one cell and clears it. Revealed letters are locked.
- Long-press cell → sheet: reveal letter, pencil mark, clear word. Undo button. Haptic tick on letter, chime on correct word (sounds optional).

Hebrew rules (locked):
- **Symbol alphabet of 27**: 22 base letters + `ג׳ ז׳ צ׳ ת׳ ד׳` as single symbols. Normalisation strips niqqud, maps final letters to base (ך→כ, ם→מ, ן→נ, ף→פ, ץ→צ), unifies geresh variants (׳ ' ’ ´) and fuses them with the preceding letter, drops gershayim, spaces, maqaf and hyphens.
- **Final letters** are never "wrong". Display rule ("across wins", geometry only): a cell shows the final form iff it is the last cell of an across word, or the last cell of a down word that belongs to no across word. Internal finals of multi-word answers are never shown; the clue carries "(2 מילים)".
- **Geresh** matching is lenient by default (typing ג for ג׳ is accepted; the geresh appears when the word is confirmed or revealed); a strict mode per level via Remote Config.
- **Spelling**: canonical כתיב מלא (Academy rules); the lexicon stores accepted variants so easy levels avoid ambiguous spellings.

English rules (locked):
- Grid is LTR: across answers start in the cell to the **right** of the clue cell (→), down answers below (↓); bent arrows mirror the Hebrew ones.
- Answers are A–Z; apostrophes, hyphens, spaces and diacritics are stripped for matching (`O'NEILL` → `ONEILL`, `CAFÉ` → `CAFE`); multi-word answers are marked "(2 words)".
- One spelling dialect per pack (US default, UK for UK-themed packs), tagged in the lexicon so a puzzle never mixes COLOR and COLOUR.
- Clue style follows UK arrowword convention: terse (≤ 20 chars), "(abbr.)", "(slang)" markers.

Language layer: every language is a `LanguageProfile` (code, reading direction, alphabet, normaliser, keyboard layouts, fonts + glyph-advance table, clue-fit budgets, clue style guide, lexicon + clue DB). Engine, generator, renderer and keyboard only talk to the profile, so a third language is content work, not engine work.

Play modes (chosen per puzzle, remembered per level):
- **רגוע / Relaxed**: instant check (each letter evaluated on entry), unlimited free checks. Max 2 stars.
- **רגיל / Normal** (default L1–L3 and easy daily): a completed word is evaluated; wrong → the word outline pulses red without pinpointing the letter; pinpointing ("check") costs coins. Up to 3 stars.
- **עיתון / Newspaper** (default L4+ and hard daily): nothing evaluated until the grid is full; then a free "יש שגיאות בתשחץ" notice without locations. 3 stars + leaderboard eligibility.
Wrong cells are marked with an icon + colour, never colour alone.

Completion screen: confetti, time, hints used, stars, coins earned (+ "double with ad"), "3 words you learned" with definitions, next puzzle / share.

### 3.2 Levels and packs
Each pack = **30 puzzles**, difficulty ramps gently inside the pack (1–10 easier, 21–30 harder). Launch with 3 packs for L1–L3, 2 for L4–L5; add packs monthly.

| Level | Name | Grid (cols×rows) | Words | Word rarity (freq rank) | Clue style | Target time |
|------|------|------------------|-------|-------------------------|------------|-------------|
| 1 | מתחילים / Starter | 7×9 | 14–18 | top 3k | direct synonyms, many 3-letter words | 3–5 min |
| 2 | קל / Easy | 8×10 | 20–24 | top 6k | synonyms, simple fill-in | 5–8 min |
| 3 | בינוני / Medium | 9×12 | 28–32 | top 12k | definitions, light trivia | 8–14 min |
| 4 | מתקדם / Hard | 10×14 | 36–42 | top 20k + proper nouns | trivia, abbreviations, indirect | 15–25 min |
| 5 | מומחה / Expert | 11×15 | 45–55 | full lexicon | indirect, wordplay, culture | 25–40 min |
| 6 (later) | מאסטר / Master | 13×17 | 60–75 | full + rare | cryptic-leaning | 40+ min |

L4+ open in a zoomed view showing ~8 columns with pan. The same table applies to English packs; English words average 5–6 letters against 4–5 in Hebrew, so English grids get one extra column from L3 up and their own length distribution; rarity bands use each language's own frequency ranks. Packs are catalogued per language; the player switches puzzle language from the home screen.

Unlock (progression model): every level's pack 1 is open from day one, so players pick their own difficulty. Inside a level, pack N+1 opens when the player has **≥ 45 of 90 stars in pack N** or has completed 20 of its 30 puzzles (Remote Config). Premium opens every pack instantly. Pack completion = badge + 150 coins + celebration. Because packs are free, content pays for itself through hints, ads and Premium, so the coin economy is deliberately a little tight.
Themed packs (same engine, theme-weighted word list): ספורט, תנ"ך, גאוגרפיה, ישראליאנה, מוזיקה, חגים (Hanukkah/Passover/Independence Day), ילדים; English: Sports, Movies, Geography, British Isles, Holidays.

### 3.3 Daily games
- Per puzzle language: **התשחץ היומי / Daily Arrowword** (easy, L2 geometry) and **האתגר היומי / Daily Challenge** (super hard, L5 geometry + clue difficulty ≥ 0.6, wordplay and proper nouns allowed). Same puzzle for everyone in that language; the puzzle for calendar date D unlocks at local midnight (server date decides leaderboard eligibility, so clock changes do not help). Dailies are never generated on-device.
- **Streak** counts if any daily is completed; "רצף מושלם" for both of a language. Streak freeze item. Streak-at-risk notification at a chosen hour.
- **Calendar archive**: last 7 days free, full archive in Premium (or 50 coins per day).
- **Leaderboard** per language for the hard daily by time (server-validated; hints add a time penalty and a marker; "no hints" filter). Top 100 + your rank; friends later.
- **Share card**: Wordle-style spoiler-free image (grid silhouette, time, streak, deep link).
- **Weekend giant** (Phase 3): Friday 15×20 puzzle solvable over the weekend.

### 3.4 Progression, rewards, retention
- Stars per puzzle (3 = no hints + under par in Normal/Newspaper; 2 = hints or Relaxed; 1 = completed).
- **XP → ranks** (טירון → מאסטר) with coin rewards; on profile and share card.
- **Achievements**: first solve, 7/30/100-day streaks, 100 words without hints, under par ×10, level completed, night owl…
- **Stats**: solve times per level, best streak, words solved, hint usage, favourite clue types; **yearly recap** in December (shareable).
- **Vocabulary book**: rare words you solved, with definitions — educational hook (both languages).
- **Smart notifications** (opt-in): daily ready, streak at risk, new pack, friend beat your time.

### 3.5 Hints catalog (starting coin prices; Remote Config)

| Hint | Cost | Notes |
|------|------|-------|
| חשיפת אות (chosen letter) | 15 | long-press cell |
| אות אקראית (random letter in word) | 10 | cheaper, adds fun |
| רמז חכם (smart letter: most crossings) | 20 | our twist |
| חשיפת מילה | 40 (L1–3) / 70 (L4–6) | |
| בדיקת מילה / בדיקת תשחץ (pinpoint errors) | 5 / 20 | free in Relaxed |
| רמז נוסף (easier alternative clue) | 10 | great for hard puzzles |
| אות ראשונה לכל מילה | 100 | power-up |
| שאל חבר (WhatsApp share of clue + pattern) | free | viral loop |
| צפייה בפרסומת → אות חינם | free | cooldown 3 min, cap 8/day |
| הקפאת רצף | 150 | |
New players get 5 free hints; confirmations have a "don't ask again" option.

### 3.6 Feature list by phase
**MVP (Phase 1)**: solving screen, keyboard, 3 play modes, hints, packs L1–L3 (3 each, progression-gated), dailies easy+hard (Hebrew), streak, coins, rewarded + interstitial ads, IAP coins/remove-ads, local save, anonymous sync, settings (text size, layout, sounds, haptics, dark mode), onboarding tutorial puzzle, basic stats, report-a-clue, **Hebrew + English UI**, language-agnostic engine with the English profile unit-tested on sample puzzles.
**Phase 2**: Premium + archive, leaderboards, achievements, share card, themes/skins (coins), XP/ranks, vocabulary book, L4–L5 packs, themed packs, push notifications, referral (invite → both get coins), Remote Config LiveOps (events, double-coin weekends), tablet layout, **English puzzle content** (packs L1–L3 + both English dailies) and the global store launch.
**Phase 3**: co-op solving (two phones, one grid), head-to-head duel, weekend giant, kids picture-תשחץ (icons as clues), seasonal pass, UGC puzzle editor with moderation, **bilingual puzzles** (English clues → Hebrew answers and the reverse, for learners), home-screen widgets, endless on-device "אימון" mode (computer-generated, unranked), English L4–L6 packs.


### 3.7 Added scope (requested after the first build)
- **Versus mode**: two players race on the same puzzle; invite by 6-character code or random matchmaking (same language and level); only progress % is shared live; the server timestamps start and finish, rejects implausible times, awards **trophies** (Elo-flavoured +10…+50 / −5…−25), coins, season points and XP; trophy leaderboard per language with leagues (עץ → אגדה).
- **Co-op mode**: up to 4 players solve one grid together in real time (shared cells with per-player colours and cursors, room code to join); completion rewards every member.
- **Free season pass**: 6-week seasons from 2026-11-02, 30 tiers × 100 points; points from battle wins/losses, dailies, missions and perfect puzzles; every tier pays coins, milestone tiers add a badge. No purchase.
- **XP and levels**: XP from puzzles (by level, bonuses for perfect/under-par/daily), battle results, co-op and missions; level curve `100·(n−1)^1.5`; rank titles טירון → מאסטר.
- **Random puzzle mode**: the generator runs on the device from a compact lexicon export (every word with a usable clue and all its fitting clues: ≈63k Hebrew words / 207k clues / 4.2 MB gz, ≈42k English / 105k / 2.2 MB gz; precomputed cell-fit flags) and the template library; the player picks a level and gets a fresh, unranked puzzle in an isolate on the device. Measured on a PC, whole build incl. clues and validation, median / worst of 6 seeds: Hebrew L1 0.08 s, L3 0.4 / 2.0 s, L4 1.3 / 3.7 s, L5 0.9 / 1.5 s; English L4 0.2 / 0.6 s, L5 0.6 / 1.9 s. Random puzzles go up to level 5 in both languages (`LevelConfig.maxDeviceLevel`); level 6 grids take ≈ 6 s on a PC, too long behind a spinner. Random puzzles accept a score up to 2.5 points outside the band at once (`BuildRequest.bandTolerance`).
- **Word bank**: 2–16-letter lists per language from the clue dictionary, Wiktionary/Wikipedia titles (Hebrew) and ENABLE + WordNet + Wiktionary (English); words without clues are reference material for clue writing and validation, not yet answers.
- **Profiles and themes**, **A→Z cycler**, **32 achievements**, **daily/weekly missions**, **picture clues** (Wikimedia Commons photos with licence credits).

---

## 4. Economy & monetisation

### 4.1 Coins: sources and sinks (starting values)
| Source | Coins | Cap |
|--------|-------|-----|
| Complete puzzle L1 / L2 / L3 / L4 / L5 | 20 / 30 / 45 / 60 / 80 | 3-star bonus +50% |
| Daily easy / hard / both | 40 / 120 / +50 | |
| Daily login (streak day 7 bonus) | 10 (50) | |
| Rewarded ad | 25 | 6/day |
| Achievement / rank up | 50–300 / 100 | |
| Starting wallet | 200 | |
Sinks: hints (§3.5), archive day (50), themes (200–500), streak freeze (150), avatar frames (100–300).
Rule of thumb: an active free player (2 puzzles + 1 daily + 2 ads a day) earns ~150/day, enough for 6–8 letter hints; a hint-heavy player runs short in 2–3 days → ads or IAP. Premium is the "comfort" purchase. Tune from data.

### 4.2 IAP catalog (ILS anchors from the market; validate against store price tiers)
| Product id | Type | Price |
|-----------|------|-------|
| `coins_300` / `coins_800` / `coins_2000` / `coins_6000` | consumable | ₪9.90 / ₪19.90 / ₪39.90 / ₪89.90 (bonus % grows) |
| `remove_ads` | non-consumable | ₪19.90 (undercut ₪24.90 incumbent) |
| `premium_monthly` / `premium_yearly` | subscription (7-day trial) | ₪12.90 / ₪69.90 → test vs ₪9.90 / ₪59.90 |
| `starter_pack` | one-time offer after 3rd puzzle | ₪4.90: 500 coins + streak freeze + exclusive theme |
Premium: no ads, every pack unlocked instantly, full daily archive, 50% hint discount, 300 coins/month, exclusive themes, weekend giant (Phase 3). Restore purchases + subscription disclosures on every paywall. One catalogue serves both languages: prices localised through store tiers (ILS, USD, GBP, EUR) and RevenueCat offerings; English markets carry higher ad eCPMs.

### 4.3 Ads policy (fair by design)
- **Order on first launch**: UMP consent (where required) → iOS ATT prompt with explainer → only then initialise the ads SDK. Non-personalised ads when consent is denied; content rating PG; "manage consent" in settings.
- **Rewarded** (user-initiated only): wallet "get coins", free letter, double completion reward, archive day. Server-side verification of rewards before coins are credited.
- **Interstitial**: only when leaving the completion screen; max 1 per 2 completed puzzles and ≥ 3 min apart; never in the first session or first 3 puzzles; never within 60 s of a rewarded ad or a purchase. All caps in Remote Config with a kill switch.
- **Never**: during solving, on launch/resume/exit, in onboarding, on paywall/wallet/leaderboard/share screens, for Premium or remove-ads owners.
- **Banner**: none on the puzzle screen; optional small banner in the pack browser; measure.

### 4.4 LiveOps
Remote Config drives prices, caps, event flags (double-coin weekend, holiday theme), paywall variants (RevenueCat offerings). Monthly cadence: new pack per language, one event, one themed daily week.

---

## 5. Content pipeline

### 5.1 Lexicon (word DB, per language)
`word_id, lang, display (ג'ינס / O'Neill), canonical, symbols[], length, lemma_id, pos, freq_rank, difficulty(0–1), word_count, flags{proper_noun, loan, acronym, slang, biblical, archaic, offensive, sensitive}, categories[], spelling_variants[], dialect (en), source, status, clue_count{full, half}`.
Hebrew (MVP, ~8k words growing to 25k+): frequency statistics from a Hebrew Wikipedia dump plus FDOSH / MILA open frequency lists; Wiktionary as editor reference (lemma inventory, not definitions); Hspell **only** as an internal spell-check oracle (AGPL, never shipped); editor-curated proper nouns and Israeliana. Licences tracked per source in `content/LICENSES.md`; legal check on anything embedded.
English (Phase 2): inventory from **ENABLE** (public domain) and **SCOWL** (permissive; check the size level), frequency from an English Wikipedia/OpenSubtitles corpus (or `wordfreq` internally only), WordNet/Wiktionary as editor references, proper nouns from Wikidata (CC0).
Word difficulty v0 = `0.55·rankScore(freq) + 0.15·lengthPenalty + 0.15·isProper + 0.10·isLoan + 0.05·hasGeresh`; later telemetry-adjusted (§5.3).

### 5.2 Clue DB and authoring
`clue_id, word_id, lang, text, style{definition, synonym, fill_in, abbreviation, trivia, wordplay, cryptic}, difficulty(0–1), min_level, max_level, fit{full:{ok, lines[]}, half:{ok, lines[]}} (precomputed per language font), author, source{editor, llm}, status{draft, approved, retired}, usage{count, last_daily{easy, hard}}, reports, stats{n, median_rel_time, hint_rate}`.
Pipeline: Python tool drafts 4–6 clues per word with an LLM (Claude Sonnet for bulk, Opus/Fable to grade), constrained in length and tagged by difficulty/style; a per-language style guide enforces newspaper conventions (Hebrew: ר"ת, "(2 מילים)", no niqqud; English: "(abbr.)", "(2 words)", one dialect per pack); a human crossword editor per language approves in the admin tool. A word is eligible for the generator only with ≥ 2 approved clues, ≥ 1 fitting a half cell. Players' "report a clue" feeds a review queue; a 1-tap admin "hide puzzle" republishes the manifest within minutes.

### 5.3 Generator (the algorithm)
**Model**: grid `cols×rows`; column 0 is the **first column in the language's reading direction** (rightmost for Hebrew, leftmost for English), so the generator never thinks about left/right. Cell = `LETTER | CLUE`. A clue has an `arrow`: `A` (across: starts in the next cell along the reading direction, runs across), `D` (starts below, runs down), `DA` (starts below, runs across), `AD` (starts in the next cell across, runs down). Extensions kept in the schema for later: `UA` (clue below the first letter, up then across) and `BD` (clue on the far side, back then down). The renderer flips glyphs per direction. A clue cell holds 1–2 clues; in a split cell the **top** half's arrow must exit through the left/right/top edge and the **bottom** half's through left/right/bottom.

**Layout rules** (validator): every maximal across run of ≥ 2 letter cells is exactly one word whose start cell is pointed at by a clue (`A` from the cell just before it in reading order or `DA` from the cell above); every down run of ≥ 2 likewise (`D` from above or `AD` from the cell before it); no letter cell is a 1-run in both directions; word length 2..level max; each clue cell serves 1–2 words with the exit-edge rule, and **no clue cell is left blank** (a hard violation since generator 0.2.1: a real arrowword has no empty squares, so a corner or border cell that cannot reach a word becomes a letter and its word gets a bent arrow); the word graph (words sharing cells) is connected; aesthetics: no 2×2 block of clue cells except the corner, no all-clue row/column except the border; soft targets scored not failed: clue-cell share 25–33 %, checked-letter ratio, 2-letter share, length histogram, bent-arrow count.

Generator parameters per level (tunable):

| Level | 2-letter max | Max word difficulty | Mean word difficulty | Min checked ratio | Bent arrows |
|------|---------------|---------------------|----------------------|-------------------|-------------|
| 1 | 35 % | 0.40 | 0.15–0.30 | 0.65 | ≤ 4 (only where a border cell would otherwise be blank) |
| 2 | 30 % | 0.55 | 0.25–0.40 | 0.60 | ≤ 5 |
| 3 | 25 % | 0.70 | 0.35–0.55 | 0.55 | ≤ 7 |
| 4 | 20 % | 0.85 | 0.50–0.65 | 0.50 | ≤ 9 |
| 5 | 15 % | 1.00 | 0.60–0.80 | 0.45 | unlimited |

**Layout generation** (offline, hybrid): start from the classic border (row 0 and column 0 are clue cells) with the cell next to the corner and 2–4 further border cells opened as letters, so the corner and every border clue cell point at a word (bent arrows `DA`/`AD`) and no square stays blank; cut each row into runs sampled from the level's length histogram; then **simulated annealing** on the clue-cell set (moves: toggle interior cell, shift a clue cell along its row, swap two cells) with energy = 1000 × hard violations + soft deviation. Runs are assigned to `(clue cell, half)` by **min-cost bipartite assignment** (cost 0 for `A`/`D`, 1 for bent arrows). Survivors are deduplicated by canonical hash and stored as a **template library** per level and language (~40–100 each) with stats, curated in the admin; hand-made shapes (holiday silhouettes) drop in the same way. Dailies pick a template by seeded RNG, excluding those used in the last 14 days of that variant.

**Fill (CSP)**:
```
index[len][pos][symbol] = Bitset(word ids)   // alphabet from the LanguageProfile (27 Hebrew symbols, 26 English letters)
domain(slot) = AND(index[len][p][grid[p]] for fixed p)            // cached per packed pattern
               AND eligible[level][slot.half?][len] AND NOT excluded[len]
               (words used elsewhere are subtracted at use time; each slot's remaining count is
                kept up to date incrementally as words are placed, so picking a slot costs O(slots))
loop:
  slot = argmin count  (ties: longer, more crossings)                                   // MRV
  if count == 0 → dead end
  for each open crossing: counts[letter] = words the crossing slot still has with that letter at the shared cell
      (exact while cheap, else the length's letter frequencies scaled to the domain size)
  candidates = domain words whose every crossing letter has counts > 0                 // letter-level forward checking, before placing
  order by −w₁·|word.diff − target| + w₂·Σ log(1 + counts[cross][letter]) + jitter(rng) // difficulty steering + least constraining value
  place(word); if no crossing slot went empty → recurse; unplace(word)
  beam: after K=24 failed candidates of a large domain, give up on this slot
  dead end → return its culprits (placed words crossing the slot or its open neighbours);
             on the way back, levels whose slot is not a culprit are skipped              // conflict-directed backjumping
  nodes++; if nodes > budget → RESTART (new rng stream, budget ×1.6)
target = clamp(levelMean + k·(levelMean − runningMean))   // difficulty steering
```
The builder gives every template one attempt first (budget 4000 nodes per 40 slots: a template that fills does so well inside it) and moves to the next on failure; only when all fail does a deep pass restart each up to 4 times. Weighting crossings more than difficulty fills faster but misses the score band, which costs more templates overall.
Rules inside the loop: no duplicate words or lemmas; words with ≥ 2 unchecked letters must be below the level's unchecked-difficulty cap; only words with an approved fitting clue are in `fitMask`, so clue assignment never fails on geometry. **Determinism**: `seed = HMAC-SHA256(secret, lang|date|variant)` for dailies, `(lang, pack, index)` for packs; output is reproducible from `(template, seed, dictionarySnapshot, generatorVersion)`, so the dictionary is **snapshotted** (versioned, Git LFS) and old puzzles stay reproducible after the lexicon changes.

**Clue assignment**: for each word, fewest-candidates first: approved clues of the lemma that fit the slot's geometry (`full` or `half`), within the level band (`min_level ≤ level ≤ max_level`, difficulty within tolerance, relaxed stepwise if empty), style allowed for the level (no wordplay/cryptic at L1–2), not used for that lemma in a daily of the same variant in the last 120 days or in the same pack, not containing another answer of the grid, and clear of the sensitive-words list; multi-word suffix appended before the fit check; weighted seeded pick favouring less-used clues; style quotas per puzzle (abbreviations ≤ 10 %, fill-ins ≤ 15 %). If nothing fits even after relaxation, the word is forbidden for that slot and the filler re-enters (rare thanks to `fitMask`).
**Fit model**: per language a glyph-advance table extracted once from the bundled clue font; budgets: full cell ≈ 3 lines × 4.4 em at 10.5 dp, half cell ≈ 2 lines × 4.8 em at 9.5 dp, greedy line breaking on spaces/maqaf, no mid-word breaks. The Flutter admin re-measures every clue cell with the real `TextPainter` and fails the review gate on overflow.

**Difficulty score** (0–100): `100·sigmoid(w·x + b)` over features {mean and p90 word difficulty, mean clue difficulty, word count, area, 2-letter share, proper-noun share, checked ratio (−), unchecked letters, average length, wordplay share, bent arrows}; bands 0–20 starter, 20–40 easy, 40–60 medium, 60–80 hard, 80–100 expert; a puzzle outside its level band is regenerated with the next attempt. **Self-calibration** (Phase 2): nightly job turns telemetry (time from word focus to solve, hint rate, wrong-entry rate, abandonment, normalised by player skill) into empirical word/clue difficulties via ridge regression + empirical-Bayes shrinkage toward the editorial prior; new weights and difficulties are committed as a new dictionary snapshot.

**Validation** (before anything is written): layout rules on the final grid; every word approved and matching its run; every clue approved and belonging to its lemma; no duplicate lemma or normalised string; blocklist on answers and clue text plus an "avoid pairs" list for unfortunate neighbours; fit; connectivity; difficulty band; schema; checksum. Ambiguity sanity: for each word count dictionary words matching only its checked letters; > 3 alternatives with a hard clue or ≥ 2 unchecked letters → warning for the reviewer.

**Daily pipeline**: CLI batch-generates 90 days ahead per language and variant as drafts → scheduled job tops the horizon up daily and alerts when fewer than 30 approved days remain → editor approves in the admin (preview, warnings, swap word/clue, regenerate) → publish function strips answers, obfuscates the solution (XOR keystream from `sha256(id + salt)`), computes the checksum, uploads `puzzles/daily/{lang}/{variant}/{date}.v{n}.json` (immutable, long cache) and rewrites `manifests/daily.json` (5-minute TTL, ETag) → the app fetches the manifest, prefetches today + 2 days, verifies checksums, caches; offline it shows the last cached daily with a clear notice.

**Performance** (measured on a PC, whole build incl. clues and validation): dictionary index + decode 0.4–0.75 s per language; L1 < 0.1 s, L2–L3 0.1–0.4 s, L4 0.2–1.3 s, L5 0.6–0.9 s median with worst seeds 2–4 s, L6 ≈ 6 s; a 30-puzzle pack in about a minute. Means: byte-array words, 32-bit bitsets with popcount, no string allocation in the hot loop, pattern cache with packed integer keys, incremental domain counts, per-crossing letter counts, conflict-directed backjumping, isolates for parallel puzzles.

### 5.4 Admin tool (Flutter web, `apps/admin`)
Lexicon/clue review queues, puzzle preview + edit (same renderer as the app, so what the reviewer approves is what players see), daily calendar with approval state and horizon alert, pack builder, template curation, flagged-clue reports, publish/hide buttons, economy dashboard (PostHog/Firestore).

---

## 6. Technical architecture

### 6.1 Stack
Flutter 3.x · Dart 3 · Riverpod (`riverpod_generator`) · go_router · drift (SQLite: progress, wallet ledger, puzzle cache index) · `shared_preferences` (settings) · freezed/json_serializable · `google_mobile_ads` (incl. UMP) · `purchases_flutter` · `firebase_core/auth/cloud_firestore/remote_config/messaging/app_check` · `sentry_flutter` · `posthog_flutter` · `share_plus` · `timezone` · Hebrew calendar/holidays via a small in-house conversion module (`kosher_dart` is LGPL-2.1, awkward for a closed-source AOT app) · bundled fonts (Noto Sans Hebrew or Heebo for Hebrew clue text, Inter/Roboto for English; evaluate legibility at 10 dp) · melos monorepo · Firebase Functions in TypeScript · Firebase Hosting (or Cloudflare) as CDN · GitHub Actions CI · fastlane/Codemagic for store delivery.

### 6.2 Repository layout (to create)
```
melos.yaml  package.json (functions tooling)  .github/workflows/{ci-core,ci-mobile,ci-functions,content-validate,release}.yml
schema/                   # puzzle.schema.json, manifest.schema.json, fixtures/ (normalisation + sample puzzles) — the Dart/TS contract
packages/core/            # Dart: puzzle model, codec, LanguageProfile (lang/he.dart, lang/en.dart), engine (navigator, validator,
                          #       hints, final-letter policy), generator (layout/anneal, layout/validate, fill, clues, difficulty), fit model
packages/render/          # Flutter: GridPainter, ArrowPainter, ClueTextLayout, keyboards, CellSemanticsOverlay (shared by app + admin)
apps/mobile/              # Flutter app; lib/features/{puzzle,packs,daily,wallet,store,ads,sync,leaderboard,achievements,share,settings,onboarding}
apps/mobile/lib/l10n/     # app_he.arb, app_en.arb
apps/mobile/assets/       # bundled tutorial + pack 1 of each level per language, fonts
apps/admin/               # Flutter web admin
tools/generate/           # Dart CLI: gen-pack, gen-dailies, validate-content, export-snapshot, publish, render-preview
tools/content/            # Python: corpus → frequency, lexicon import, LLM clue drafting, style-guide checks
functions/                # TS: revenuecatWebhook, ledgerOnWrite, reconcileWallet, admobSsv, submitDaily, publishPuzzle,
                          #     generateDailiesJob (alerting), serverTime, calibrateClues, streakReminders, deleteAccount
firebase/                 # firestore.rules, firestore.indexes.json, storage.rules, remoteconfig.template.json
content/{he,en}/{lexicon,clues,templates,puzzles}/   # versioned data per language (JSONL/JSON)
content/snapshots/        # pinned dictionary snapshots for reproducible generation (Git LFS)
content/blocklist/        # offensive, sensitive, avoid_pairs per language;  content/LICENSES.md
docs/                     # this plan, adr/, content-style-guide-{he,en}.md, economy.md, schema docs
```

### 6.3 Puzzle JSON (schema v1, sketch)
```jsonc
{ "schemaVersion": 1, "lang": "he", "id": "he-d-2026-11-01-hard", "kind": "daily",      // pack | daily | tutorial
  "level": 5, "daily": {"date": "2026-11-01", "variant": "hard"}, "pack": null,         // {"id":"he-l2-003","index":17} for packs
  "grid": {"cols": 11, "rows": 15, "colOrigin": "readingStart"},
  "layout": ["CCCCCCCCCCC", "CLLLCLLLLLL", "..."],                                     // row strings: L letter, C clue
  "clueCells": [ {"r": 1, "c": 0, "slots": [
      {"pos": "top",    "wordId": "a01", "arrow": "A", "text": "עיר בנגב", "lines": ["עיר", "בנגב"]},
      {"pos": "bottom", "wordId": "d01", "arrow": "D", "text": "ר\"ת: ראש הממשלה", "lines": ["ר\"ת: ראש", "הממשלה"]} ]} ],
  "words": [ {"id": "a01", "dir": "A", "start": {"r": 1, "c": 1}, "len": 6, "clueCell": {"r": 1, "c": 0}, "arrow": "A",
              "clueId": "c_008812", "lemmaId": "l_055120", "wordCount": 2, "difficulty": 0.31} ],
  "solution": {"enc": "xor1", "data": "base64…"},                                     // one symbol per letter cell, row-major
  "difficulty": {"score": 78, "band": "hard", "features": {"meanWordDiff": 0.61, "checkedRatio": 0.52, "...": 0}},
  "meta": {"generator": {"version": "1.0.0", "seed": "…", "templateId": "he-t-11x15-014", "dictSnapshot": "he-2026-10-01-ab12"},
           "reviewer": "…", "publishedAt": "…", "version": 1, "checksum": "sha256:…"} }
```
`c` counts from the first column in reading direction. The **authoring variant** (admin/Firestore only) adds `answer`, `displayForm`, candidate clue ids, `review{status, notes}` and `warnings[]`. Solutions ship obfuscated, not secret: leaderboard integrity comes from server-side checks. Manifests: `daily.json` (per language and variant: date, id, url, checksum, version; last 365 + next 3 days) and `packs.json` (id, lang, level, index, title, puzzleCount, url, checksum, free). Pack files are immutable with versioned filenames.

### 6.4 Client modules and state
`puzzle_engine` (pure Dart: `Puzzle`, `PuzzleProgress`, `Navigator` for active word/cursor/direction/auto-advance, `Validator`, `FinalLetterPolicy`, `HintService`, `CompletionDetector`), `grid_renderer` (CustomPainter with repaint boundaries; layers cells → clue text/arrows → letters → highlights; `ClueTextLayout` caches `TextPainter`s per cell size; direction from the puzzle's LanguageProfile; `CellSemanticsOverlay`), `keyboard` (layouts per language), `hints`, `wallet` (local ledger + reconciliation), `store` (RevenueCat offerings/paywall/restore/entitlements `noAds`, `premium`), `ads` (consent flow, loader with caps), `content` (manifests, prefetch, cache, checksum), `sync` (anonymous → linked auth; per-cell last-writer-wins merge with monotone counters), `daily` (date logic, streaks, result submission), `analytics`, `settings`, `a11y` (seniors preset).

Saved puzzle state (drift table `puzzle_progress`): `puzzleId, puzzleVersion, cells[]{symbol?, status: empty|filled|confirmedCorrect|markedWrong|revealed, updatedAt}, elapsedMs (active time only), lettersRevealed, wordsRevealed, checksUsed, wrongEntries, completed, completedAt, perfect, stars, mode, startedAt, lastPlayedAt, revision, activeWordId, cursorCell`. Autosave debounced 500 ms and immediately on hint/completion/pause. Indexed columns let pack screens show progress without decoding blobs.

### 6.5 Backend
- **Auth**: anonymous by default; link Apple/Google for sync and restore (Sign in with Apple is mandatory once Google sign-in is offered); in-app account deletion.
- **Firestore**: `users/{uid}` (profile, wallet{balance}, entitlements), `users/{uid}/progress/{puzzleId}`, `users/{uid}/ledger/{entryId}` (create-only by owner), `users/{uid}/daily/{lang}_{date}_{variant}`, `leaderboards/{lang}_{date}_{variant}/entries/{uid}`, `puzzlesAuthoring/{id}`, `words`, `clues`, `templates`.
- **Wallet ledger**: client appends entries (`UUIDv7 id, type, amount, balanceAfter, refId, deviceId, syncState`); `ledgerOnWrite` validates each entry (earn types within Remote Config bounds, `earn_complete` requires a completed progress doc and is once per puzzle, `earn_ad` requires a server-side-verified AdMob reward record and daily caps, daily/streak earns require a daily result) and updates the authoritative balance in a transaction; rejected entries are marked with a reason; the client appends a `reconcile` entry when its balance differs. Spending works offline; server is authoritative; local tampering is bounded to cosmetic effects.
- **Purchases**: `purchases_flutter` with the Firebase uid as app user id → RevenueCat webhook (shared-secret header) → idempotent ledger entry `rc_{eventId}` for coin bundles, negative entry on refund, entitlements mirrored to Firestore for server-side gating (archive, leaderboards); client reads entitlements from the SDK (works offline). Coins show as "pending" until the ledger entry lands, with a 60 s fallback that pulls the subscriber from RevenueCat server-side.
- **Leaderboard**: `submitDaily` callable behind App Check: puzzle is a daily within 2 days, one submission per uid, solution hash matches, `elapsedMs ≥ 0.7 s × letter cells`, progress completed; score = time + penalties per hint/check and per mode; top 100 + rank via aggregated percentile buckets.
- **Functions**: `publishPuzzle`, `generateDailiesJob` (horizon top-up + alert), `serverTime`, `calibrateClues` (nightly), `streakReminders` (FCM), `deleteAccount`. Security rules: owner-only progress, create-only ledger, read-only wallet.
- **Remote Config**: economy table, hint prices, ad caps, unlock thresholds, feature flags, event banners.

### 6.6 Analytics events (PostHog)
`puzzle_start/complete {level, mode, time, hints, stars}`, `word_solved {clue_id, dt}`, `hint_used {type, cost}`, `check_used`, `ad_requested/shown/rewarded {placement}`, `paywall_view/purchase {product}`, `pack_unlock`, `daily_open/complete`, `streak_change`, `onboarding_step`, `a11y_setting_changed`, `language_switched`. Every event carries `lang` (puzzle language) and `ui_lang`; difficulty calibration runs per language. Funnels: install → tutorial → first complete → D1/D7/D30.

### 6.7 Accessibility & bidi
The painter is excluded from semantics; a `CellSemanticsOverlay` places one semantics node per cell in reading order ("אות 2 מתוך 4, מילה מאוזן: עיר בנגב, האות שין", tappable); clue cells read their clue and arrow; announcements for word completed / error / puzzle completed / clue change; keyboard keys labelled by letter name so TTS pronounces them; focus order grid → clue bar → keyboard; dynamic type everywhere except inside clue cells (which scale with grid zoom); WCAG AA palette + high-contrast theme; status never by colour alone; reduced-motion variants; 48 dp targets (keys ≥ 52 dp); **seniors preset** (fewer columns on screen, bigger keys, Relaxed mode, haptics). App chrome follows the UI locale (he RTL / en LTR via `flutter_localizations` + ARB); the grid, clue bar and keyboard follow the **puzzle** language's direction independently (an English grid stays LTR inside a Hebrew UI); golden tests for all four combinations.

---

## 7. Roadmap

| Phase | Weeks | Scope | Done when |
|-------|-------|-------|-----------|
| 0 Foundation | 1–5 | Monorepo; `core` model + codec + JSON Schema + LanguageProfile (he, en) + validator; hand-made sample puzzle per language rendered on device; Hebrew lexicon v0 (~8k words with frequency, POS, flags; licences documented); clue style guide; ~3k LLM-drafted clues human-approved; layout annealer + template library for L1–L3; filler + clue assignment + difficulty v0; CLI with preview; design system in Figma; store accounts; brand name | 100 puzzles across L1–L5 generate in < 5 min with ≥ 95 % fill success per template; determinism test green; editor rates ≥ 80 % of L1–L3 puzzles publishable without edits; solving prototype tested with 5 people incl. 2 seniors |
| 1 MVP | 6–16 | Everything in §3.6 MVP (Hebrew puzzles, Hebrew + English UI); admin v0 (dailies board, preview, approve/reject/regenerate, publish); dailies on CDN; functions (webhook, ledger, publish, server time, delete account); IAP + ads in sandbox; closed beta (TestFlight / Play internal, 50–100 testers, 2 weeks) | Crash-free ≥ 99.5 %; median solve times inside level targets; tutorial completion ≥ 80 %; purchases and restores verified on both stores; store review passed; 90 approved dailies in the pipeline |
| 2 Growth | 17–24 | §3.6 Phase 2 (Premium, leaderboards with App Check, achievements, share, themes, L4–L5, LiveOps, referral, tablet, difficulty calibration from telemetry, AdMob server-side verification, admin v1 with word/clue CRUD and overflow checker) + English lexicon/clues (editor hired), English packs L1–L3, English dailies, US/UK/CA/AU launch | D7 retention ≥ 20 %; calibrated difficulty correlates with observed solve time (Spearman ≥ 0.6); zero P1 issues from a VoiceOver/TalkBack audit; English soft launch live with its own difficulty targets met |
| 3 Expansion | months 7–10 | §3.6 Phase 3 (co-op/duel, weekend giant, kids, pass, UGC, bilingual, widgets, endless mode, English L4–L6) | Chosen by Phase 2 data |

Team: 1 Flutter dev (+1 from Phase 2), 1 full-stack/content-tools (can be the same person early), 1 Hebrew crossword editor/content lead (part-time → full), 1 English-speaking crossword editor (part-time, from Phase 2), designer part-time, beta groups in both languages. Content cadence: ≥ 1 new pack per level per language per month; dailies approved ≥ 2 weeks ahead.

---

## 8. Store & compliance checklist
Apple Developer + Play Console; bundle ids and flavours (dev/prod); IAP products mirrored in RevenueCat; restore purchases; subscription screen with price, period, auto-renew text, terms/privacy links; Sign in with Apple; in-app account deletion; privacy policy + terms (he/en); App Privacy labels and Data Safety form (ads SDK declared, privacy manifests); UMP + ATT before ads init; age rating; Hebrew and English listings, screenshots and preview videos; name/subtitle with "תשחץ" and "Arrowword" keywords; markets Israel first, then US/UK/CA/AU; trademark check in both scripts; Israeli privacy/consumer-law review of the subscription flow; accessibility statement.

---

## 9. Risks & mitigations
- **Clue quality/volume** → editor approval gate, LLM drafts, report-a-clue, telemetry re-rating; launch with fewer, better packs.
- **Legibility of in-cell clues** → fit model + admin overflow gate, clue bar as the primary reading surface, auto-zoom ≥ 44 dp cells, tap-to-enlarge popover, tests with 55+ users.
- **Ad fatigue** (incumbent's main complaint) → rewarded-first, hard caps, consent-first init, Remote Config kill switch.
- **Store rejection** → paywall checklist, sandbox tests, Sign in with Apple, account deletion, no external payment links.
- **Lexicon/clue licensing** → own lexicon and original clues, Hspell internal only, licences tracked per source, lawyer review.
- **Hebrew/bidi rendering bugs** → logical coordinates (grid never relies on `Directionality`), bundled fonts, golden tests across pixel ratios and OEM fonts, custom keyboard avoids OS autocorrect.
- **Final letters / geresh disputes** → normalised matching, geometry display rule, lenient geresh, report button.
- **Battery/performance** (incumbent complaint) → repaint boundaries, no idle animations, cached text layouts, profiling on low-end Android.
- **Leaderboard cheating / coin farming** → server-bounded earns, verified ad rewards, App Check, plausibility checks, server-authoritative purchases; accept cosmetic local tampering.
- **Generator dead-ends on hard grids** → dictionary growth for 7–10-letter words, arc consistency + restarts, layout mutation, template retirement by observed fill-failure rate.
- **Offensive or politically sensitive content** → blocklists for answers and clue text, avoid-pairs, mandatory human approval for dailies, 1-tap hide via manifest republish.
- **Daily rollover/timezone bugs** → date-keyed puzzles, server date for eligibility, prefetch 2 days, dailies published ≥ 7 days ahead, horizon alerting.
- **English market** → small niche with dated apps next to giant crossword apps; position on "Arrowword", start with 3 levels + dailies, let data decide investment.
- **Two content pipelines** double editorial cost → shared tooling; hire the English editor only once Hebrew is proven.
- **Mixed-direction UI** → grid, clue bar and keyboard own their direction; golden tests for all four combinations.

---

## 10. Verification (how each part gets tested)
- **core**: every test runs for both LanguageProfiles; normaliser conformance fixtures shared with the TS functions; layout validator on hand-built good/bad layouts (isolated letter, over-capacity clue cell, border run without bent arrow, disconnected, 2×2 clue block); min-cost assignment correctness; property tests (every annealed layout passes the validator; every filled puzzle satisfies run↔word bijection, crossing consistency, no duplicates, all words in the snapshot); determinism (same template/seed/snapshot/version → identical checksum); pattern index equals brute force on random dictionaries; difficulty monotonicity; CI benchmark asserting p95 fill time per level.
- **content CI**: every puzzle JSON validates against the schema and the full validator; blocklist scan; checksum recomputation; fit re-measured.
- **engine (Dart unit)**: navigation rules, final-letter mask, lenient geresh, completion detection, hint locking, ledger arithmetic, conflict merge, date rollover incl. DST.
- **rendering goldens**: each arrow type and slot, split cells, final forms, geresh glyphs, RTL and LTR, light/dark, high contrast, text scale 1.0/1.3/2.0, pixel ratios 2/3; both keyboards.
- **widget/integration**: keyboard → letter, backspace semantics, next/prev word, clue popover, hint confirmations, paywall text; end-to-end solve of a sample puzzle; purchase + restore via StoreKit config and Play license testers through RevenueCat sandbox; rewarded/interstitial with test ad ids; offline launch plays bundled content; daily fetch with stubbed manifest.
- **accessibility**: `flutter_test` guidelines (tap targets, labels, contrast) on every screen; scripted TalkBack/VoiceOver walkthrough per release (open daily, solve a word, use a hint, buy coins); switch-control/keyboard-only check.
- **backend**: emulator tests for webhook idempotency (duplicate event ids), ledger validation (over-cap earns rejected), leaderboard plausibility, security rules.
- **beta**: 50–100 testers per language; completion rate, median time per level vs targets, hint usage, crash-free rate, interviews with 5 seniors.

## 11. References used
Competitors: "התשחץ שלי" (App Store id1137440163), "תשחץ יומי" (App Store id6762508535, Google Play `il.co.kitapp.daily.crossword`), English arrowword apps on the App Store (Crosswords Plus, Arrowword PuzzleLife, Crossword Daily - Arrow Word). Licences: Hspell FAQ (hspell.sourceforge.net/about.html), ENABLE/SCOWL notes (Debian copyright files), wordfreq licence. Arrowword editor reference: github.com/Leo-Nicolle/mots-fleches (MIT).

## 12. First build steps (when you say go)
1. Scaffold the monorepo (melos) with `schema/`, `packages/core`, `packages/render`, `apps/mobile`, `tools/generate`, `functions`, `content/`.
2. Implement the puzzle model, codec, JSON Schema, LanguageProfile (he, en) with normalisers and the layout validator, all with tests; hand-author one 7×9 sample puzzle per language.
3. Build the solving-screen prototype (grid painter, keyboard, clue bar, input model) and run it on a phone.
4. Hebrew lexicon v0 + first drafted clues; layout annealer + templates; filler + clue assignment; generate 10 puzzles per level for editor review.
5. Wire wallet, hints, local save; then manifests/dailies, ads, IAP sandbox; then beta.
