import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/util/clock.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../puzzle/application/progress_providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final stats = ref.watch(playerStatsProvider);
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
      body: stats.solved == 0 && history.totalCompleted == 0
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
                    tile(Icons.extension_rounded, l10n.statsSolved, '${stats.solved}'),
                    tile(Icons.star_rounded, l10n.statsStars, '${stats.stars}'),
                    tile(Icons.emoji_events_outlined, l10n.statsPerfect, '${stats.perfect}'),
                    tile(Icons.lightbulb_outline_rounded, l10n.statsHints, '${stats.hints}'),
                    tile(Icons.today_rounded, l10n.statsDailies, '${stats.dailies}'),
                    tile(Icons.local_fire_department_rounded, l10n.bestStreak(history.bestStreak()), l10n.streakDays(streak)),
                  ],
                ),
                if (stats.bestTimeByLevel.isNotEmpty) ...[
                  SectionHeader(l10n.completionTime),
                  for (final e in (stats.bestTimeByLevel.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
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
