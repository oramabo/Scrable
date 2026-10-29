import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ledger', () {
    test('initial wallet holds the starting grant', () {
      final l = Ledger.initial(startingWallet: 200, now: 1000);
      expect(l.balance, 200);
      expect(l.entries.single.type, LedgerEntryType.earnLogin);
      expect(l.entries.single.refId, Ledger.welcomeRef);
      expect(l.entries.single.balanceAfter, 200);
    });

    test('earn is idempotent per (type, refId)', () {
      var l = Ledger.initial(startingWallet: 200, now: 1);
      l = l.earn(LedgerEntryType.earnComplete, 20, refId: 'he-l1-p01-01', now: 2);
      l = l.earn(LedgerEntryType.earnComplete, 20, refId: 'he-l1-p01-01', now: 3);
      expect(l.balance, 220);
      expect(l.entries.length, 2);
      // Same refId, different type is a different grant.
      l = l.earn(LedgerEntryType.earnDaily, 40, refId: 'he-l1-p01-01', now: 4);
      expect(l.balance, 260);
    });

    test('spend reduces the balance and refuses when short', () {
      var l = Ledger.initial(startingWallet: 30, now: 1);
      l = l.spend(LedgerEntryType.spendLetter, 15, refId: 'p:reveal_letter:1', now: 2);
      expect(l.balance, 15);
      expect(l.entries.last.amount, -15);
      expect(l.entries.last.balanceAfter, 15);
      expect(
        () => l.spend(LedgerEntryType.spendWord, 40, refId: 'p:reveal_word:2', now: 3),
        throwsA(isA<InsufficientCoinsException>()),
      );
      expect(l.canSpend(15), isTrue);
      expect(l.canSpend(16), isFalse);
    });

    test('zero or negative amounts are ignored', () {
      final l = Ledger.initial(startingWallet: 10, now: 1);
      expect(identical(l.earn(LedgerEntryType.earnAd, 0, refId: 'x', now: 2), l), isTrue);
      expect(identical(l.spend(LedgerEntryType.spendCheck, 0, refId: 'y', now: 2), l), isTrue);
    });

    test('reconcile appends the difference to the server balance', () {
      var l = Ledger.initial(startingWallet: 200, now: 1);
      l = l.reconcileTo(180, now: 5);
      expect(l.balance, 180);
      expect(l.entries.last.type, LedgerEntryType.reconcile);
      expect(l.entries.last.amount, -20);
      expect(identical(l.reconcileTo(180, now: 6), l), isTrue);
    });

    test('sync state bookkeeping', () {
      var l = Ledger.initial(startingWallet: 200, now: 1)
          .earn(LedgerEntryType.earnComplete, 20, refId: 'a', now: 2)
          .earn(LedgerEntryType.earnComplete, 30, refId: 'b', now: 3);
      expect(l.pendingEntries.length, 3);
      l = l.markSynced([l.entries[0].id, l.entries[1].id]);
      expect(l.pendingEntries.length, 1);
      l = l.markSynced([l.entries[2].id], state: SyncState.rejected);
      expect(l.pendingEntries, isEmpty);
      expect(l.entries[2].syncState, SyncState.rejected);
    });

    test('json round trip keeps entries, free hints and items', () {
      final l = Ledger.initial(startingWallet: 200, now: 1)
          .spend(LedgerEntryType.spendItem, 150, refId: 'freeze:1', now: 2)
          .copyWith(freeHintsUsed: 3, streakFreezes: 1);
      final back = Ledger.fromJson(l.toJson());
      expect(back.balance, 50);
      expect(back.entries.length, 2);
      expect(back.entries[1].type, LedgerEntryType.spendItem);
      expect(back.freeHintsUsed, 3);
      expect(back.streakFreezes, 1);
      expect(back.hasEntry(LedgerEntryType.earnLogin, Ledger.welcomeRef), isTrue);
    });

    test('entry ids are unique within a ledger', () {
      var l = Ledger.initial(startingWallet: 200, now: 1);
      for (var i = 0; i < 20; i++) {
        l = l.earn(LedgerEntryType.earnAd, 25, refId: 'ad:$i', now: 1);
      }
      expect(l.entries.map((e) => e.id).toSet().length, l.entries.length);
    });
  });
}
