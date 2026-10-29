import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'store_service.dart';

class EntitlementsController extends Notifier<Entitlements> {
  @override
  Entitlements build() {
    final store = ref.watch(storeServiceProvider);
    final sub = store.entitlementsStream.listen((e) => state = e);
    ref.onDispose(sub.cancel);
    return store.entitlements;
  }

  /// For tests and for the Premium flag without a store build.
  void set(Entitlements e) => state = e;
}

final entitlementsProvider = NotifierProvider<EntitlementsController, Entitlements>(EntitlementsController.new);

final isPremiumProvider = Provider<bool>((ref) => ref.watch(entitlementsProvider).premium);
final adsFreeProvider = Provider<bool>((ref) => ref.watch(entitlementsProvider).adsFree);

final storeOfferingsProvider = FutureProvider<List<StoreProductInfo>>((ref) async {
  final store = ref.watch(storeServiceProvider);
  if (!store.available) return const [];
  return store.offerings();
});
