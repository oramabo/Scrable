import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'ledger.dart';

class WalletController extends Notifier<Ledger> {
  @override
  Ledger build() => ref.read(bootstrapProvider).ledger;

  int get _now => ref.read(clockProvider).nowMs;

  void _set(Ledger next) {
    if (identical(next, state)) return;
    state = next;
    ref.read(walletRepositoryProvider).save(next).ignore();
  }

  bool canAfford(int amount) => state.canSpend(amount);

  /// Returns false (and changes nothing) when the balance is too low.
  bool spend(LedgerEntryType type, int amount, {required String refId}) {
    try {
      _set(state.spend(type, amount, refId: refId, now: _now));
      return true;
    } on InsufficientCoinsException {
      return false;
    }
  }

  /// Idempotent per (type, refId).
  void earn(LedgerEntryType type, int amount, {required String refId}) =>
      _set(state.earn(type, amount, refId: refId, now: _now));

  int freeHintsLeft() {
    final total = ref.read(gameConfigProvider).freeHints;
    final left = total - state.freeHintsUsed;
    return left < 0 ? 0 : left;
  }

  void useFreeHint() => _set(state.copyWith(freeHintsUsed: state.freeHintsUsed + 1));

  /// Daily login bonus (once per local date); day-7 streak bonus when
  /// [streak] is a positive multiple of 7.
  bool grantLoginBonus({required String date, required int streak}) {
    final config = ref.read(gameConfigProvider);
    final ref0 = 'login:$date';
    if (state.hasEntry(LedgerEntryType.earnLogin, ref0)) return false;
    final amount = streak > 0 && streak % 7 == 0 ? config.loginBonusDay7 : config.loginBonus;
    earn(LedgerEntryType.earnLogin, amount, refId: ref0);
    return true;
  }

  void creditPurchase({required String transactionId, required int coins}) =>
      earn(LedgerEntryType.purchaseBundle, coins, refId: 'rc:$transactionId');

  void addStreakFreeze() => _set(state.copyWith(streakFreezes: state.streakFreezes + 1));

  bool consumeStreakFreeze() {
    if (state.streakFreezes <= 0) return false;
    _set(state.copyWith(streakFreezes: state.streakFreezes - 1));
    return true;
  }

  /// Pushes pending entries to the cloud and reconciles to the server balance.
  Future<void> syncWithCloud() async {
    final cloud = ref.read(cloudSyncProvider);
    if (!cloud.enabled || state.pendingEntries.isEmpty) return;
    final result = await cloud.syncLedger(state);
    if (result == null) return;
    var next = state.markSynced(result.acceptedIds).markSynced(result.rejectedIds, state: SyncState.rejected);
    next = next.reconcileTo(result.serverBalance, now: _now);
    _set(next);
  }

  void reset() => _set(Ledger.initial(startingWallet: ref.read(gameConfigProvider).startingWallet, now: _now));
}

final walletProvider = NotifierProvider<WalletController, Ledger>(WalletController.new);

final balanceProvider = Provider<int>((ref) => ref.watch(walletProvider).balance);

final freeHintsLeftProvider = Provider<int>((ref) {
  final total = ref.watch(gameConfigProvider).freeHints;
  final used = ref.watch(walletProvider).freeHintsUsed;
  return (total - used).clamp(0, total);
});
