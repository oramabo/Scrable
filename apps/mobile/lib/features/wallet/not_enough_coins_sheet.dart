import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../ads/ads_service.dart';
import 'ledger.dart';
import 'wallet_controller.dart';

/// Shown when a hint costs more than the balance. Offers a rewarded ad (when
/// ads are enabled) and the store. Returns true when coins were earned so
/// the caller can retry.
Future<bool> showNotEnoughCoinsSheet(BuildContext context, WidgetRef ref, {required int needed}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    builder: (_) => _NotEnoughCoinsSheet(needed: needed),
  );
  return result ?? false;
}

class _NotEnoughCoinsSheet extends ConsumerStatefulWidget {
  const _NotEnoughCoinsSheet({required this.needed});
  final int needed;

  @override
  ConsumerState<_NotEnoughCoinsSheet> createState() => _NotEnoughCoinsSheetState();
}

class _NotEnoughCoinsSheetState extends ConsumerState<_NotEnoughCoinsSheet> {
  bool _busy = false;

  Future<void> _watchAd() async {
    setState(() => _busy = true);
    final ads = ref.read(adsServiceProvider);
    final outcome = await ads.showRewarded(AdPlacements.walletTopUp);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == RewardedOutcome.rewarded) {
      final coins = ref.read(gameConfigProvider).rewardedAdCoins;
      ref.read(walletProvider.notifier).earn(
            LedgerEntryType.earnAd,
            coins,
            refId: 'ad:${ref.read(clockProvider).nowMs}',
          );
      showSnack(context, context.l10n.adRewardEarned(coins));
      Navigator.of(context).pop(ref.read(balanceProvider) >= widget.needed);
    } else {
      showSnack(context, context.l10n.adUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final balance = ref.watch(balanceProvider);
    final ads = ref.watch(adsServiceProvider);
    final store = ref.watch(storeServiceProvider);
    final rewardCoins = ref.watch(gameConfigProvider).rewardedAdCoins;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.notEnoughCoins, style: theme.textTheme.titleLarge)),
                CoinChip(balance: balance, compact: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.notEnoughCoinsBody(widget.needed, balance), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 20),
            if (ads.enabled)
              FilledButton.icon(
                onPressed: _busy ? null : _watchAd,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: Text(l10n.watchAdForCoins(rewardCoins)),
              ),
            if (ads.enabled) const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(false);
                context.push('/store');
              },
              icon: const Icon(Icons.storefront_outlined),
              label: Text(l10n.buyCoins),
            ),
            if (!store.available)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.storeDisabledHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
