# Chetz UX/UI direction — fun, sticky, effortless

This is the design brief the app follows. Every rule has a reason; when a rule and a reason disagree, the reason wins.

## 1. Principles
1. **Zero friction to the first letter.** A new player types a letter within 20 seconds of install: no sign-up, no settings, one tutorial grid that teaches by doing. Every screen has one obvious primary action.
2. **Thumb-first, grandparent-proof.** Everything important sits in the bottom 60 % of the screen; targets ≥ 48 dp; text never below 14 sp outside the grid; the grid never below 44 dp per cell (auto-zoom). Hebrew first-class: RTL layouts, Hebrew numerals never, Hebrew typography that breathes.
3. **Juice without noise.** Every correct action gets a tiny, fast reward (≤ 250 ms): a cell pop, a soft tick, a colour wash across a completed word. Wrong actions are gentle (a short shake, muted colour), never punishing. Reduced-motion users get fades instead of movement; sounds default to off during quiet hours.
4. **Always a next thing.** The completion screen and the home screen always offer exactly one suggested next action (continue pack, today's daily, a mission one step from done, a friend's rematch). Never a dead end, never a wall of options.
5. **Fair and transparent economy.** Prices are visible before any tap; the first hints are free; ads are opt-in and clearly labelled; "watch for coins" is a choice, never a surprise.

## 2. Visual identity
- **Mood**: a warm paper notebook that came alive. Light theme: paper `#F7F3EA`, ink `#1F2937`, grid lines `#C9C2B2`, clue cells `#EFE9DC`, accent **arrow orange** `#F28C28` (primary CTA, active word), teal `#1F8A8A` (correct), coral `#E25D5D` (wrong, always with an icon), gold `#E0B64A` (coins/stars). Dark theme: slate `#141A22` / `#1E2733`, ink `#E8E6E1`, same accents desaturated 10 %. High-contrast theme: pure black/white with the orange accent. Custom theme: the player picks primary, background and highlight; the picker shows a live grid preview and refuses combinations under 4.5:1 contrast.
- **Type**: Noto Sans Hebrew (UI, grid letters 600 weight) and Inter (English). Grid letters are large and centred; in-cell clue text is 10–11 dp, but the clue bar is 20 dp, so nobody squints.
- **Shape**: 16 dp rounded cards, 12 dp buttons, cells square with 2 dp gaps, one soft shadow level. The arrow glyph is the brand mark: it appears in the logo, loading indicator and streak flame.
- **Motion**: 120–250 ms ease-out; springy only for rewards (coins fly to the counter, stars pop one by one); never block input with animation.

## 3. Information architecture
Bottom bar (4 tabs, labels always visible): **משחק / Play** (home) · **יומי / Daily** · **מולטי / Play Together** (versus + co-op + leaderboards) · **אני / Me** (profile, achievements, season pass, stats, settings).
Home = "continue" card (last puzzle, progress ring) → daily cards (easy/hard with streak flame and timer to reset) → missions strip (3 chips with progress) → packs by level (horizontal shelves) → random puzzle button ("תשחץ אקראי", choose level in a sheet).

## 4. The solving screen (the product)
- Grid top, clue bar middle, keyboard bottom; the active clue is always readable without looking at the cell. Tap a clue cell → popover with its 1–2 clues and arrows. Tap letter cell → select; tap again → switch direction (animate the highlight sliding).
- Keyboard keys 52 dp tall with a 180 ms press preview; the **A→Z key** appears (slide-in) only when one empty cell remains in the word; long-press runs letters at 4/s with a soft tick per letter.
- Feedback: correct word → letters wash teal left-to-right (RTL aware) + light haptic; wrong word (normal mode) → outline shakes 2× and fades, no red letters; completion → grid flips cell by cell (≤ 900 ms total), confetti burst, stars pop, coins fly into the counter, then the summary card slides up with ONE primary button (next puzzle / claim mission / rematch).
- Timer hidden by default; a subtle progress ring on the top bar shows % of letters filled instead (positive framing).
- Hint sheet: three big cards (letter, word, check) with prices and a "watch ad → free letter" card when ads are enabled; the first 5 hints show a "חינם" badge.
- Error states speak human: "משהו לא מתאים במילה הזאת" not "incorrect".

## 5. First-time experience (FTUE)
Splash (≤ 1 s, arrow draws itself) → one screen: "איך נקרא לך?" (optional name, skip) → tutorial puzzle 5×6 with 3 coach marks (tap clue, type, A→Z) → first completion gives 100 coins + the first achievement + "your first daily is ready" card. No permission prompts before the first completion; notifications are asked after the second daily with a reason ("נשמור על הרצף שלך").

## 6. Retention loops (what brings people back)
- **Streak** with a flame that grows (3/7/30 days change its look); streak-at-risk push at the player's usual hour; one streak freeze earned per 7 days.
- **Missions**: 3 daily (reset midnight) + 3 weekly (Monday); progress chips on home; claiming is a satisfying button, not automatic.
- **Season pass** (free): a horizontal track with 30 tiers, the next tier always visible on home ("עוד 35 נקודות לפרס"); battle wins feel doubly rewarding because the track moves.
- **Trophies & leagues**: a league badge on the profile and on the versus lobby; promotion/relegation moments get a full-screen celebration.
- **Collections**: achievements grid, vocabulary book ("מילים שלמדת"), picture credits (people like seeing what they solved).
- **Social**: spoiler-free share card after dailies and battles; rematch button; invite code copy/share via WhatsApp.

## 7. Multiplayer feel
- Versus lobby: big "מצא יריב" button with a 20-second pulse, invite code card with copy/share; opponent found → both avatars slide in, 3-2-1 countdown, go.
- During the race only a thin dual progress bar at the top (you vs. them); no chat, no distraction. Finish → results card with trophy delta animation, season points and XP bars filling, "משחק חוזר" primary.
- Co-op: each player a colour; letters typed by others appear with their colour for 1 s then settle; cursors shown as small coloured arrows; a "ready?" check before start; completion celebrates all avatars together.

## 8. Ease-of-use guardrails
- Seniors preset (one tap in onboarding and settings): 125 % text, high contrast, relaxed mode, big keyboard, haptics on, timer off.
- Undo is always one tap; accidental hint taps need a confirm (with "don't ask again").
- Everything works offline; sync happens silently; the app never shows a spinner on launch (local cache first).
- Interruptions: incoming call/background → progress is saved instantly; coming back shows the same cell selected.

## 9. Copy tone
Short, warm, second person, no exclamation storms. Hebrew: "יופי, עוד מילה" · "כמעט — נסו אות אחרת" · "הרצף שלך: 4 ימים". English: "Nice, one more" · "Almost — try another letter" · "Your streak: 4 days". Numbers always with units; coins always with the coin icon.

## 10. What we measure to tune fun
Tutorial completion rate, time to first completed puzzle, D1/D7/D30, dailies per active day, hint usage per level, A→Z use, mission claim rate, battle rematch rate, rage-quit rate (puzzle abandoned < 2 minutes after a wrong-word pulse), accessibility preset adoption. Targets are in docs/GAME_PLAN.md §7.
