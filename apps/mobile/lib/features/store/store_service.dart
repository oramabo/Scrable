import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/analytics/analytics.dart';
import '../../core/config/app_config.dart';

/// Product ids from docs/GAME_PLAN.md §4.2.
abstract final class ProductIds {
  static const coins300 = 'coins_300';
  static const coins800 = 'coins_800';
  static const coins2000 = 'coins_2000';
  static const coins6000 = 'coins_6000';
  static const removeAds = 'remove_ads';
  static const premiumMonthly = 'premium_monthly';
  static const premiumYearly = 'premium_yearly';
  static const starterPack = 'starter_pack';

  static const coinAmounts = {coins300: 300, coins800: 800, coins2000: 2000, coins6000: 6000, starterPack: 500};
}

abstract final class EntitlementIds {
  static const premium = 'premium';
  static const removeAds = 'remove_ads';
}

@immutable
class Entitlements {
  const Entitlements({this.premium = false, this.removeAds = false});
  final bool premium;
  final bool removeAds;

  /// Premium includes no ads.
  bool get adsFree => premium || removeAds;

  static const none = Entitlements();

  Map<String, dynamic> toJson() => {'premium': premium, 'removeAds': removeAds};
  static Entitlements fromJson(Map<String, dynamic> j) =>
      Entitlements(premium: (j['premium'] as bool?) ?? false, removeAds: (j['removeAds'] as bool?) ?? false);
}

class StoreProductInfo {
  const StoreProductInfo({
    required this.id,
    required this.title,
    required this.priceString,
    this.description = '',
    this.coins,
  });

  final String id;
  final String title;
  final String description;
  final String priceString;

  /// Coins granted for a consumable bundle.
  final int? coins;
}

enum PurchaseStatus { success, cancelled, failed, unavailable }

class PurchaseOutcome {
  const PurchaseOutcome(this.status, {this.transactionId, this.coins, this.entitlements = Entitlements.none});
  final PurchaseStatus status;
  final String? transactionId;
  final int? coins;
  final Entitlements entitlements;
}

/// RevenueCat-backed store behind an interface. [DisabledStoreService] when
/// IAP is off; [FakeStoreService] in tests.
abstract class StoreService {
  const StoreService();

  bool get available;
  Entitlements get entitlements;
  Stream<Entitlements> get entitlementsStream;

  Future<void> initialize({String? appUserId});
  Future<List<StoreProductInfo>> offerings();
  Future<PurchaseOutcome> purchase(String productId);
  Future<Entitlements> restore();
}

class DisabledStoreService extends StoreService {
  const DisabledStoreService();
  @override
  bool get available => false;
  @override
  Entitlements get entitlements => Entitlements.none;
  @override
  Stream<Entitlements> get entitlementsStream => const Stream.empty();
  @override
  Future<void> initialize({String? appUserId}) async {}
  @override
  Future<List<StoreProductInfo>> offerings() async => const [];
  @override
  Future<PurchaseOutcome> purchase(String productId) async => const PurchaseOutcome(PurchaseStatus.unavailable);
  @override
  Future<Entitlements> restore() async => Entitlements.none;
}

class FakeStoreService extends StoreService {
  FakeStoreService({Entitlements initial = Entitlements.none, this.products = const []}) : _entitlements = initial;

  Entitlements _entitlements;
  final List<StoreProductInfo> products;
  final _controller = StreamController<Entitlements>.broadcast();
  final List<String> purchases = [];

  @override
  bool get available => true;
  @override
  Entitlements get entitlements => _entitlements;
  @override
  Stream<Entitlements> get entitlementsStream => _controller.stream;

  set entitlements(Entitlements e) {
    _entitlements = e;
    _controller.add(e);
  }

  @override
  Future<void> initialize({String? appUserId}) async {}
  @override
  Future<List<StoreProductInfo>> offerings() async => products;
  @override
  Future<PurchaseOutcome> purchase(String productId) async {
    purchases.add(productId);
    if (productId == ProductIds.removeAds) entitlements = Entitlements(premium: _entitlements.premium, removeAds: true);
    if (productId.startsWith('premium')) entitlements = const Entitlements(premium: true, removeAds: true);
    return PurchaseOutcome(
      PurchaseStatus.success,
      transactionId: 'fake-${purchases.length}',
      coins: ProductIds.coinAmounts[productId],
      entitlements: _entitlements,
    );
  }

  @override
  Future<Entitlements> restore() async => _entitlements;
}

class RevenueCatStoreService extends StoreService {
  RevenueCatStoreService({required this.appConfig, required this.analytics});

  final AppConfig appConfig;
  final Analytics analytics;

  Entitlements _entitlements = Entitlements.none;
  final _controller = StreamController<Entitlements>.broadcast();
  bool _configured = false;
  Offerings? _offerings;

  @override
  bool get available => _configured;
  @override
  Entitlements get entitlements => _entitlements;
  @override
  Stream<Entitlements> get entitlementsStream => _controller.stream;

  @override
  Future<void> initialize({String? appUserId}) async {
    if (!appConfig.iapEnabled || appConfig.revenueCatApiKey.isEmpty || _configured) return;
    try {
      final cfg = PurchasesConfiguration(appConfig.revenueCatApiKey)..appUserID = appUserId;
      await Purchases.configure(cfg);
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _onCustomerInfo(await Purchases.getCustomerInfo());
      _configured = true;
    } catch (e) {
      debugPrint('store init failed: $e');
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active;
    _entitlements = Entitlements(
      premium: active.containsKey(EntitlementIds.premium),
      removeAds: active.containsKey(EntitlementIds.removeAds),
    );
    _controller.add(_entitlements);
  }

  @override
  Future<List<StoreProductInfo>> offerings() async {
    if (!_configured) return const [];
    try {
      _offerings ??= await Purchases.getOfferings();
      final packages = _offerings?.current?.availablePackages ?? const <Package>[];
      analytics.track(AnalyticsEvents.paywallView, {'products': packages.length});
      return [
        for (final p in packages)
          StoreProductInfo(
            id: p.storeProduct.identifier,
            title: p.storeProduct.title,
            description: p.storeProduct.description,
            priceString: p.storeProduct.priceString,
            coins: ProductIds.coinAmounts[p.storeProduct.identifier],
          ),
      ];
    } catch (e) {
      debugPrint('offerings failed: $e');
      return const [];
    }
  }

  @override
  Future<PurchaseOutcome> purchase(String productId) async {
    if (!_configured) return const PurchaseOutcome(PurchaseStatus.unavailable);
    try {
      _offerings ??= await Purchases.getOfferings();
      Package? package;
      for (final p in _offerings?.current?.availablePackages ?? const <Package>[]) {
        if (p.storeProduct.identifier == productId) package = p;
      }
      if (package == null) return const PurchaseOutcome(PurchaseStatus.unavailable);
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _onCustomerInfo(result.customerInfo);
      analytics.track(AnalyticsEvents.purchase, {'product': productId});
      return PurchaseOutcome(
        PurchaseStatus.success,
        transactionId: result.storeTransaction.transactionIdentifier,
        coins: ProductIds.coinAmounts[productId],
        entitlements: _entitlements,
      );
    } on PurchasesErrorCode {
      return const PurchaseOutcome(PurchaseStatus.failed);
    } catch (e) {
      final text = e.toString();
      if (text.contains('PURCHASE_CANCELLED') || text.contains('1')) {
        return const PurchaseOutcome(PurchaseStatus.cancelled);
      }
      return const PurchaseOutcome(PurchaseStatus.failed);
    }
  }

  @override
  Future<Entitlements> restore() async {
    if (!_configured) return _entitlements;
    try {
      _onCustomerInfo(await Purchases.restorePurchases());
    } catch (e) {
      debugPrint('restore failed: $e');
    }
    return _entitlements;
  }
}
