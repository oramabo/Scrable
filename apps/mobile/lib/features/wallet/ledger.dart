import '../../core/storage/json_store.dart';

/// Ledger entry kinds, matching the server-side validator in functions/.
enum LedgerEntryType {
  earnComplete('earn_complete'),
  earnDaily('earn_daily'),
  earnAd('earn_ad'),
  earnLogin('earn_login'),
  earnAchievement('earn_achievement'),
  earnMission('earn_mission'),
  earnSeason('earn_season'),
  spendLetter('spend_letter'),
  spendWord('spend_word'),
  spendCheck('spend_check'),
  spendItem('spend_item'),
  purchaseBundle('purchase_bundle'),
  reconcile('reconcile');

  const LedgerEntryType(this.code);
  final String code;

  bool get isSpend => code.startsWith('spend_');

  static LedgerEntryType fromCode(String code) =>
      LedgerEntryType.values.firstWhere((t) => t.code == code, orElse: () => LedgerEntryType.reconcile);
}

enum SyncState { pending, synced, rejected }

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.refId,
    required this.createdAt,
    this.syncState = SyncState.pending,
  });

  final String id;
  final LedgerEntryType type;

  /// Signed: positive earns, negative spends.
  final int amount;
  final int balanceAfter;

  /// Idempotency key: puzzle id, `login:2026-10-28`, `daily:2026-10-28:easy`…
  final String refId;
  final int createdAt;
  final SyncState syncState;

  LedgerEntry copyWith({SyncState? syncState}) => LedgerEntry(
        id: id,
        type: type,
        amount: amount,
        balanceAfter: balanceAfter,
        refId: refId,
        createdAt: createdAt,
        syncState: syncState ?? this.syncState,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.code,
        'amount': amount,
        'balanceAfter': balanceAfter,
        'refId': refId,
        'createdAt': createdAt,
        'sync': syncState.name,
      };

  static LedgerEntry fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as String,
        type: LedgerEntryType.fromCode(j['type'] as String),
        amount: j['amount'] as int,
        balanceAfter: (j['balanceAfter'] as int?) ?? 0,
        refId: (j['refId'] as String?) ?? '',
        createdAt: (j['createdAt'] as int?) ?? 0,
        syncState: SyncState.values.firstWhere((s) => s.name == j['sync'], orElse: () => SyncState.pending),
      );
}

class InsufficientCoinsException implements Exception {
  const InsufficientCoinsException({required this.needed, required this.balance});
  final int needed;
  final int balance;
  @override
  String toString() => 'InsufficientCoins(needed $needed, balance $balance)';
}

/// Append-only coin ledger. Balance is derived from the entries; the wallet
/// file also carries the free-hint counter and owned items.
class Ledger {
  Ledger({List<LedgerEntry> entries = const [], this.freeHintsUsed = 0, this.streakFreezes = 0})
      : entries = List.unmodifiable(entries);

  /// A new wallet with the starting grant.
  factory Ledger.initial({required int startingWallet, required int now}) => Ledger().earn(
        LedgerEntryType.earnLogin,
        startingWallet,
        refId: welcomeRef,
        now: now,
      );

  static const welcomeRef = 'welcome';

  final List<LedgerEntry> entries;
  final int freeHintsUsed;
  final int streakFreezes;

  int get balance => entries.fold(0, (sum, e) => sum + e.amount);
  bool get isEmpty => entries.isEmpty;

  bool hasEntry(LedgerEntryType type, String refId) => entries.any((e) => e.type == type && e.refId == refId);

  int countOn(LedgerEntryType type, {required bool Function(LedgerEntry) where}) =>
      entries.where((e) => e.type == type && where(e)).length;

  bool canSpend(int amount) => balance >= amount;

  /// Adds coins. Idempotent per (type, refId): a repeated earn returns `this`.
  Ledger earn(LedgerEntryType type, int amount, {required String refId, required int now}) {
    if (amount <= 0 || hasEntry(type, refId)) return this;
    return _append(type, amount, refId, now);
  }

  /// Removes coins; throws [InsufficientCoinsException] when short.
  Ledger spend(LedgerEntryType type, int amount, {required String refId, required int now}) {
    if (amount <= 0) return this;
    if (!canSpend(amount)) throw InsufficientCoinsException(needed: amount, balance: balance);
    return _append(type, -amount, refId, now);
  }

  /// Adjusts the local balance to a server-authoritative value.
  Ledger reconcileTo(int serverBalance, {required int now}) {
    final diff = serverBalance - balance;
    if (diff == 0) return this;
    return _append(LedgerEntryType.reconcile, diff, 'reconcile:$now', now);
  }

  Ledger _append(LedgerEntryType type, int signedAmount, String refId, int now) {
    final next = balance + signedAmount;
    final entry = LedgerEntry(
      id: '${now.toRadixString(36)}-${entries.length.toRadixString(36)}',
      type: type,
      amount: signedAmount,
      balanceAfter: next,
      refId: refId,
      createdAt: now,
    );
    return copyWith(entries: [...entries, entry]);
  }

  Ledger copyWith({List<LedgerEntry>? entries, int? freeHintsUsed, int? streakFreezes}) => Ledger(
        entries: entries ?? this.entries,
        freeHintsUsed: freeHintsUsed ?? this.freeHintsUsed,
        streakFreezes: streakFreezes ?? this.streakFreezes,
      );

  Ledger markSynced(Iterable<String> ids, {SyncState state = SyncState.synced}) {
    final set = ids.toSet();
    return copyWith(entries: [for (final e in entries) set.contains(e.id) ? e.copyWith(syncState: state) : e]);
  }

  List<LedgerEntry> get pendingEntries => entries.where((e) => e.syncState == SyncState.pending).toList();

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'freeHintsUsed': freeHintsUsed,
        'streakFreezes': streakFreezes,
      };

  static Ledger fromJson(Map<String, dynamic> j) => Ledger(
        entries: ((j['entries'] as List?) ?? const []).map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>)).toList(),
        freeHintsUsed: (j['freeHintsUsed'] as int?) ?? 0,
        streakFreezes: (j['streakFreezes'] as int?) ?? 0,
      );
}

abstract class WalletRepository {
  Future<Ledger?> load();
  Future<void> save(Ledger ledger);
}

class JsonWalletRepository implements WalletRepository {
  JsonWalletRepository(this.store, {this.key = 'wallet/ledger'});

  final JsonStore store;
  final String key;

  @override
  Future<Ledger?> load() async {
    final j = await store.read(key);
    return j == null ? null : Ledger.fromJson(j);
  }

  @override
  Future<void> save(Ledger ledger) => store.write(key, ledger.toJson());
}
