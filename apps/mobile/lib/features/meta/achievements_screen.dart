import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_controller.dart';
import 'game_events_controller.dart';

IconData achievementIcon(String hint) => switch (hint) {
      'flag' => Icons.flag_rounded,
      'grid' => Icons.grid_on_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'sparkle' => Icons.auto_awesome_rounded,
      'calendar' => Icons.today_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'bolt' => Icons.bolt_rounded,
      'box' => Icons.inventory_2_rounded,
      'stairs' => Icons.stairs_rounded,
      'crown' => Icons.workspace_premium_rounded,
      'book' => Icons.menu_book_rounded,
      'timer' => Icons.timer_rounded,
      'newspaper' => Icons.newspaper_rounded,
      'moon' => Icons.nightlight_round,
      'sun' => Icons.wb_sunny_rounded,
      'globe' => Icons.public_rounded,
      'abc' => Icons.abc_rounded,
      'share' => Icons.share_rounded,
      'coins' => Icons.monetization_on_rounded,
      _ => Icons.star_rounded,
    };

Color tierColor(AchievementTier tier) => switch (tier) {
      AchievementTier.bronze => const Color(0xFFB87333),
      AchievementTier.silver => const Color(0xFF8E9AAF),
      AchievementTier.gold => const Color(0xFFE0A526),
      AchievementTier.platinum => const Color(0xFF5B8DEF),
    };

/// All 32 achievements grouped by tier with progress, lock state and reward.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final stats = ref.watch(playerStatsProvider);
    final lang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final unlocked = Achievements.all.where((a) => a.isUnlocked(stats)).length;

    String tierName(AchievementTier t) => switch (t) {
          AchievementTier.bronze => l10n.tierBronze,
          AchievementTier.silver => l10n.tierSilver,
          AchievementTier.gold => l10n.tierGold,
          AchievementTier.platinum => l10n.tierPlatinum,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.achievementsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.achievementsUnlocked(unlocked, Achievements.all.length), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: unlocked / Achievements.all.length, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          for (final tier in AchievementTier.values) ...[
            SectionHeader(tierName(tier)),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 176,
              ),
              itemCount: Achievements.all.where((a) => a.tier == tier).length,
              itemBuilder: (context, i) {
                final a = Achievements.all.where((x) => x.tier == tier).elementAt(i);
                return _AchievementCard(achievement: a, stats: stats, lang: lang, tierLabel: tierName(tier));
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement, required this.stats, required this.lang, required this.tierLabel});

  final Achievement achievement;
  final PlayerStats stats;
  final String lang;
  final String tierLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final a = achievement;
    final done = a.isUnlocked(stats);
    final progress = a.progress(stats).clamp(0, a.threshold);
    final color = tierColor(a.tier);
    final status = done ? l10n.achievementUnlockedLabel : l10n.achievementLocked;
    return Semantics(
      label: '${a.title(lang)}, $tierLabel, $status, $progress/${a.threshold}, ${l10n.missionReward(a.rewardCoins)}',
      child: ExcludeSemantics(
        child: Card(
          color: done ? color.withValues(alpha: 0.14) : null,
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: done ? color : theme.colorScheme.surfaceContainerHighest, shape: BoxShape.circle),
                      child: Icon(
                        done ? achievementIcon(a.icon) : Icons.lock_outline_rounded,
                        size: 20,
                        color: done ? Colors.white : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.monetization_on_rounded, size: 14, color: Color(0xFFE0B64A)),
                          const SizedBox(width: 2),
                          Flexible(child: Text('+${a.rewardCoins}', style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(a.title(lang), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Expanded(child: Text(a.description(lang), style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: a.fraction(stats),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: done ? color : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$progress/${a.threshold}', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
