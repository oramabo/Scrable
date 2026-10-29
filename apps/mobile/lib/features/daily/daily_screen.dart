import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../puzzle/application/progress_providers.dart';
import '../settings/settings_controller.dart';
import '../store/store_providers.dart';
import '../wallet/ledger.dart';
import '../wallet/wallet_controller.dart';
import 'daily_controller.dart';

/// Daily tab: streak, today's two puzzles, 7-day archive (more with Premium)
/// and the streak-freeze item.
class DailyTab extends ConsumerWidget {
  const DailyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final history = ref.watch(dailyHistoryProvider);
    final streak = ref.watch(streakProvider);
    final atRisk = ref.watch(streakAtRiskProvider);
    final premium = ref.watch(isPremiumProvider);
    final config = ref.watch(gameConfigProvider);
    final clock = ref.watch(clockProvider);
    final freezes = ref.watch(walletProvider).streakFreezes;
    final dates = archiveDates(clock.now(), premium ? 30 : config.archiveFreeDays);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, size: 40, color: streak > 0 ? const Color(0xFFE0652A) : theme.colorScheme.outline),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.streakDays(streak), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text(l10n.bestStreak(history.bestStreak()), style: theme.textTheme.bodyMedium),
                        if (atRisk) Text(l10n.streakAtRisk, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SectionHeader(l10n.today),
          _DailyRow(date: today, isToday: true),
          SectionHeader(l10n.archiveTitle),
          for (final d in dates.skip(1)) _DailyRow(date: d, isToday: false),
          if (!premium)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.archivePremium, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          SectionHeader(l10n.streakFreeze),
          ActionCard(
            icon: Icons.ac_unit_rounded,
            title: freezes > 0 ? l10n.streakFreezeOwned : l10n.streakFreeze,
            subtitle: l10n.streakFreezeDescription,
            trailing: freezes > 0
                ? Text('×$freezes', style: theme.textTheme.titleMedium)
                : FilledButton.tonal(
                    onPressed: () {
                      final wallet = ref.read(walletProvider.notifier);
                      final ok = wallet.spend(
                        LedgerEntryType.spendItem,
                        config.streakFreezePrice,
                        refId: 'freeze:${ref.read(clockProvider).nowMs}',
                      );
                      if (ok) {
                        wallet.addStreakFreeze();
                      } else {
                        showSnack(context, l10n.notEnoughCoins);
                      }
                    },
                    child: Text(l10n.streakFreezeBuy(config.streakFreezePrice)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DailyRow extends ConsumerWidget {
  const _DailyRow({required this.date, required this.isToday});
  final String date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final history = ref.watch(dailyHistoryProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(isToday ? '${l10n.today} · $date' : date, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                IconButton(
                  tooltip: l10n.leaderboardTitle,
                  onPressed: () => context.push('/leaderboard/$date?lang=${ref.read(settingsProvider).puzzleLang}'),
                  icon: const Icon(Icons.leaderboard_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final v in DailyVariant.values) ...[
                  Expanded(child: _VariantChip(date: date, variant: v, done: history.isCompleted(date, v))),
                  if (v == DailyVariant.easy) const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantChip extends ConsumerWidget {
  const _VariantChip({required this.date, required this.variant, required this.done});
  final String date;
  final DailyVariant variant;
  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final id = ref.watch(dailyPuzzleIdProvider((date, variant))).value;
    final available = ref.watch(dailyAvailableProvider((date, variant))).value ?? false;
    final summary = id == null ? null : ref.watch(progressSummaryProvider(id));
    final completed = done || (summary?.completed ?? false);
    final label = variant == DailyVariant.easy ? l10n.dailyEasyShort : l10n.dailyHardShort;
    final status = completed
        ? l10n.dailyCompleted
        : (summary?.inProgress ?? false)
            ? l10n.dailyInProgress
            : available
                ? l10n.dailyPlay
                : l10n.dailyUnavailable;
    return OutlinedButton.icon(
      onPressed: id != null && available ? () => context.push('/play/$id') : null,
      icon: Icon(completed ? Icons.check_circle_rounded : (variant == DailyVariant.easy ? Icons.wb_sunny_outlined : Icons.local_fire_department_outlined)),
      label: Text('$label · $status', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
