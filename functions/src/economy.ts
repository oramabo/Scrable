/**
 * Coin economy constants: the server-side validation bounds for the wallet
 * ledger and the product catalogue. Mirrors docs/GAME_PLAN.md §3.5 (hints),
 * §4.1 (coin sources and sinks) and §4.2 (IAP catalogue). Live prices and
 * caps are served to the app through Remote Config
 * (firebase/remoteconfig.template.json); the numbers here are the ceilings a
 * client-submitted entry may not exceed.
 */

export const EARN_TYPES = [
  'earn_complete',
  'earn_perfect',
  'earn_daily',
  'earn_streak',
  'earn_ad',
  'earn_achievement',
  'earn_login',
] as const;
export type EarnType = (typeof EARN_TYPES)[number];

export const SPEND_TYPES = ['spend_letter', 'spend_word', 'spend_check', 'spend_item'] as const;
export type SpendType = (typeof SPEND_TYPES)[number];

/** Types only Cloud Functions may write; rejected when a client submits them. */
export const SERVER_ONLY_TYPES = ['purchase_bundle', 'refund', 'admin_adjust'] as const;
export type ServerOnlyType = (typeof SERVER_ONLY_TYPES)[number];

export const LEDGER_TYPES = [...EARN_TYPES, ...SPEND_TYPES, ...SERVER_ONLY_TYPES, 'reconcile'] as const;
export type LedgerType = (typeof LEDGER_TYPES)[number];

export function isEarnType(t: string): t is EarnType {
  return (EARN_TYPES as readonly string[]).includes(t);
}
export function isSpendType(t: string): t is SpendType {
  return (SPEND_TYPES as readonly string[]).includes(t);
}
export function isServerOnlyType(t: string): t is ServerOnlyType {
  return (SERVER_ONLY_TYPES as readonly string[]).includes(t);
}
export function isLedgerType(t: string): t is LedgerType {
  return (LEDGER_TYPES as readonly string[]).includes(t);
}

/** Consumable coin products (RevenueCat / store product ids) and the coins they grant. */
export const COIN_PRODUCTS: Readonly<Record<string, number>> = {
  coins_300: 300,
  coins_800: 800,
  coins_2000: 2000,
  coins_6000: 6000,
  /** One-time starter offer: 500 coins (+ streak freeze + theme granted client-side). */
  starter_pack: 500,
};

/** Non-consumable / subscription products and the entitlement each unlocks. */
export const ENTITLEMENT_IDS = ['premium', 'remove_ads'] as const;
export type EntitlementId = (typeof ENTITLEMENT_IDS)[number];
export function isEntitlementId(id: string): id is EntitlementId {
  return (ENTITLEMENT_IDS as readonly string[]).includes(id);
}

/** Coins every new wallet starts with (§4.1). */
export const STARTING_WALLET = 200;

/** Completion reward per level; 3-star completion adds 50 %. */
export const COMPLETE_REWARD_BY_LEVEL: Readonly<Record<number, number>> = { 1: 20, 2: 30, 3: 45, 4: 60, 5: 80 };
export const THREE_STAR_BONUS = 0.5;

export const DAILY_REWARD = { easy: 40, hard: 120, both: 50 } as const;
export const LOGIN_REWARD = { base: 10, streakDay7: 50 } as const;
export const AD_REWARD = { coins: 25, perDay: 6, cooldownSec: 180, freeLetterPerDay: 8 } as const;
export const ACHIEVEMENT_REWARD = { min: 50, max: 300, rankUp: 100 } as const;

/** Hint prices in coins (§3.5). */
export const HINT_PRICES = {
  revealLetter: 15,
  randomLetter: 10,
  smartLetter: 20,
  revealWordLow: 40, // levels 1–3
  revealWordHigh: 70, // levels 4–6
  checkWord: 5,
  checkPuzzle: 20,
  alternativeClue: 10,
  firstLetters: 100,
  streakFreeze: 150,
} as const;

/** Other sinks (§4.1). */
export const ITEM_PRICES = {
  archiveDay: 50,
  themeMin: 200,
  themeMax: 500,
  streakFreeze: 150,
  avatarFrameMin: 100,
  avatarFrameMax: 300,
} as const;

export interface EarnRule {
  /** Largest amount a single entry may carry. */
  max: number;
  /** Maximum number of accepted entries of this type per UTC day. */
  perDay?: number;
  /** The entry's refId may be credited only once (e.g. one earn_complete per puzzle). */
  oncePerRef?: boolean;
}

/** Validation bounds for client-submitted earn entries. */
export const EARN_RULES: Readonly<Record<EarnType, EarnRule>> = {
  // 80 (L5) × 1.5 three-star bonus = 120, once per puzzle id.
  earn_complete: { max: 120, oncePerRef: true },
  // Perfect (no hints) bonus, once per puzzle id.
  earn_perfect: { max: 40, oncePerRef: true },
  // hard (120) + both-variants bonus (50), once per daily puzzle id.
  earn_daily: { max: 170, oncePerRef: true },
  earn_streak: { max: 100, perDay: 1 },
  earn_ad: { max: 30, perDay: 6 },
  earn_achievement: { max: 300, perDay: 20 },
  earn_login: { max: 50, perDay: 1 },
};

/** Largest absolute amount a client-submitted spend of each type may carry (catalogue price × 1). */
export const SPEND_LIMITS: Readonly<Record<SpendType, number>> = {
  spend_letter: Math.max(HINT_PRICES.revealLetter, HINT_PRICES.randomLetter, HINT_PRICES.smartLetter),
  spend_word: HINT_PRICES.revealWordHigh,
  spend_check: Math.max(HINT_PRICES.checkWord, HINT_PRICES.checkPuzzle),
  spend_item: Math.max(ITEM_PRICES.themeMax, ITEM_PRICES.avatarFrameMax, HINT_PRICES.firstLetters, HINT_PRICES.streakFreeze, ITEM_PRICES.archiveDay),
};

/** Entries a single syncLedger call may carry. */
export const MAX_ENTRIES_PER_SYNC = 100;

/** Leaderboard plausibility and scoring (§6.5). */
export const DAILY_MIN_MS_PER_LETTER = 700;
export const DAILY_SUBMISSION_WINDOW_DAYS = 2;
export const PENALTY_MS = { letterRevealed: 20_000, wordRevealed: 60_000, checkUsed: 15_000 } as const;
export const MODE_TIME_FACTOR: Readonly<Record<'relaxed' | 'normal' | 'newspaper', number>> = {
  relaxed: 0.15,
  normal: 0.05,
  newspaper: 0,
};
