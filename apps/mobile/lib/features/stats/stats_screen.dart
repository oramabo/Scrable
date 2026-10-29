import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/util/clock.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../meta/game_events_controller.dart';
import '../puzzle/application/progress_providers.dart';

/// Lifetime statistics: counters from the meta layer's `PlayerStats`, stars
/// and best times from the progress index, streak from the daily history.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final stats = ref.watch(playerStatsProvider);
    final aggregates = ref.watch(progressAggregatesProvider);
    final history = ref.watch(dailyHistoryProvider);
    final streak = ref.watch(streakProvider);

    Widget tile(IconData icon, String label, String value) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              label: label,
              value: value,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(label, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: stats.puzzlesCompleted == 0 && history.totalCompleted == 0
          ? EmptyState(icon: Icons.bar_chart_rounded, message: l10n.statsEmpty)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.4,
                  children: [
                    tile(Icons.extension_rounded, l10n.statsSolved, '${stats.puzzlesCompleted}'),
                    tile(Icons.star_rounded, l10n.statsStars, '${aggregates.stars}'),
                    tile(Icons.emoji_events_outlined, l10n.statsPerfect, '${stats.perfectPuzzles}'),
                    tile(Icons.lightbulb_outline_rounded, l10n.statsHints, '${stats.hintsUsed}'),
                    tile(Icons.today_rounded, l10n.statsDailies, '${stats.dailiesCompleted}'),
                    tile(Icons.local_fire_department_rounded, l10n.bestStreak(history.bestStreak()), l10n.streakDays(streak)),
                    tile(Icons.menu_book_outlined, l10n.statsWords, '${stats.wordsSolved}'),
                    tile(Icons.monetization_on_outlined, l10n.statsCoinsEarned, '${stats.coinsEarned}'),
                  ],
                ),
                if (aggregates.bestTimeByLevel.isNotEmpty) ...[
                  SectionHeader(l10n.completionTime),
                  for (final e in (aggregates.bestTimeByLevel.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(l10n.statsBestTime(e.key)),
                      trailing: Text(formatDuration(e.value), style: theme.textTheme.titleMedium),
                    ),
                ],
              ],
            ),
    );
  }
}
