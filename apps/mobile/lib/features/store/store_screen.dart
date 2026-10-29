import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../wallet/wallet_controller.dart';
import 'store_providers.dart';
import 'store_service.dart';

/// Coins, remove-ads and Premium. Reads offerings from the store service;
/// shows a friendly notice when IAP is disabled in this build.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  Future<void> _buy(BuildContext context, WidgetRef ref, StoreProductInfo p) async {
    final l10n = context.l10n;
    final store = ref.read(storeServiceProvider);
    final outcome = await store.purchase(p.id);
    if (!context.mounted) return;
    switch (outcome.status) {
      case PurchaseStatus.success:
        if (outcome.coins != null && outcome.transactionId != null) {
          ref.read(walletProvider.notifier).creditPurchase(transactionId: outcome.transactionId!, coins: outcome.coins!);
        }
        ref.read(entitlementsProvider.notifier).set(outcome.entitlements);
        await ref.read(adsServiceProvider).recordPurchase();
        if (context.mounted) showSnack(context, l10n.purchaseDone);
      case PurchaseStatus.cancelled:
        break;
      case PurchaseStatus.failed:
      case PurchaseStatus.unavailable:
        showSnack(context, l10n.purchaseFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final store = ref.watch(storeServiceProvider);
    final offerings = ref.watch(storeOfferingsProvider);
    final entitlements = ref.watch(entitlementsProvider);
    final balance = ref.watch(balanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeTitle),
        actions: [Padding(padding: const EdgeInsets.only(right: 8, left: 8), child: CoinChip(balance: balance))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.workspace_premium_rounded, color: theme.colorScheme.primary, size: 36),
              title: Text(l10n.premium, style: theme.textTheme.titleLarge),
              subtitle: Text(l10n.premiumDescription),
              trailing: entitlements.premium ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32)) : null,
            ),
          ),
          const SizedBox(height: 16),
          if (!store.available)
            EmptyState(icon: Icons.storefront_outlined, message: '${l10n.storeUnavailable}\n${l10n.storeDisabledHint}')
          else
            offerings.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              error: (e, _) => EmptyState(icon: Icons.error_outline, message: l10n.errorGeneric),
              data: (products) => Column(
                children: [
                  for (final p in products)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(
                          p.coins != null ? Icons.monetization_on_rounded : Icons.block_rounded,
                          color: p.coins != null ? const Color(0xFFE0A526) : theme.colorScheme.primary,
                        ),
                        title: Text(p.title),
                        subtitle: p.description.isEmpty ? null : Text(p.description),
                        trailing: FilledButton(onPressed: () => _buy(context, ref, p), child: Text(p.priceString)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: store.available
                ? () async {
                    final e = await store.restore();
                    ref.read(entitlementsProvider.notifier).set(e);
                    if (context.mounted) showSnack(context, l10n.restoreDone);
                  }
                : null,
            icon: const Icon(Icons.restore_rounded),
            label: Text(l10n.restorePurchases),
          ),
        ],
      ),
    );
  }
}
