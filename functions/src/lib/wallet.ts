import { STARTING_WALLET } from '../economy';
import { type DocData, type DocSnapshot, getField, readNumber } from './firestore';

/** Fixed id of the server-authored entry that seeds a new wallet with STARTING_WALLET coins. */
export const STARTING_WALLET_ENTRY_ID = 'starting_wallet';

export interface WalletRead {
  balance: number;
  /** True when the user document has no wallet yet: the caller must write the starting entry. */
  needsSeed: boolean;
}

/** Authoritative balance from `users/{uid}.wallet.balance`, or the starting wallet for a new user. */
export function readWallet(user: DocSnapshot): WalletRead {
  if (getField(user.data, 'wallet') === undefined) return { balance: STARTING_WALLET, needsSeed: true };
  return { balance: readNumber(user.data, 'wallet.balance', 0), needsSeed: false };
}

export function startingWalletEntry(now: number): DocData {
  return {
    id: STARTING_WALLET_ENTRY_ID,
    type: 'admin_adjust',
    amount: STARTING_WALLET,
    balanceAfter: STARTING_WALLET,
    createdAt: now,
    deviceId: 'server',
    refId: STARTING_WALLET_ENTRY_ID,
    server: { status: 'accepted', source: 'server', syncedAt: now, appliedAmount: STARTING_WALLET },
  };
}

export function walletUpdate(balance: number, now: number): DocData {
  return { wallet: { balance, updatedAt: now } };
}
