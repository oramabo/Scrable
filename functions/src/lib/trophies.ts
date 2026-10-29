/**
 * Trophy formula for versus races (README "Multiplayer › Trophies").
 *
 * Elo expectation E = 1 / (1 + 10^((opponent − me) / 400)). A win pays
 * `winBase ± k·kScale·(0.5 − E)` = 30 ± 20 → clamped to [10, 50]: beating a
 * much stronger player pays +50, beating a much weaker one +10. A loss costs
 * `lossBase + k·kScale·(E − 0.5)` = 15 ± 10 → clamped to [5, 25]: losing to a
 * much weaker player costs −25, to a much stronger one −5. A draw moves
 * nothing; a forfeit is a loss. Trophies never go below 0.
 */
import { TROPHY_RULES } from '../economy';

export type MatchResult = 'win' | 'loss' | 'draw' | 'forfeit';

function clamp(v: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, v));
}

/** Probability that a player with `mine` trophies beats one with `theirs`. */
export function expectedScore(mine: number, theirs: number): number {
  return 1 / (1 + Math.pow(10, (theirs - mine) / TROPHY_RULES.eloDivisor));
}

/** Trophies gained by the winner (always positive, in [winMin, winMax]). */
export function winDelta(winnerTrophies: number, loserTrophies: number): number {
  const swing = TROPHY_RULES.k * TROPHY_RULES.kScale;
  const raw = TROPHY_RULES.winBase + swing * (0.5 - expectedScore(winnerTrophies, loserTrophies));
  return clamp(Math.round(raw), TROPHY_RULES.winMin, TROPHY_RULES.winMax);
}

/** Trophies lost by the loser (always negative, in [−lossMax, −lossMin]). */
export function lossDelta(loserTrophies: number, winnerTrophies: number): number {
  const swing = TROPHY_RULES.k * TROPHY_RULES.kScale;
  const raw = TROPHY_RULES.lossBase + swing * (expectedScore(loserTrophies, winnerTrophies) - 0.5);
  return -clamp(Math.round(raw), TROPHY_RULES.lossMin, TROPHY_RULES.lossMax);
}

/** Signed trophy delta for one player given the result and both current totals. */
export function trophyDelta(result: MatchResult, mine: number, theirs: number): number {
  switch (result) {
    case 'win':
      return winDelta(mine, theirs);
    case 'loss':
    case 'forfeit':
      return lossDelta(mine, theirs);
    case 'draw':
      return 0;
  }
}

/** New trophy total: never below zero. */
export function applyTrophyDelta(current: number, delta: number): number {
  return Math.max(0, Math.round(current + delta));
}
