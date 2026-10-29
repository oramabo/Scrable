import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../meta/game_events_controller.dart';
import '../settings/settings_controller.dart';
import 'multiplayer_providers.dart';

/// "Play Together" tab (UX §3/§7): versus races, co-op rooms, the trophy
/// board and the hard-daily leaderboard. Multiplayer needs cloud sync.
class TogetherTab extends ConsumerWidget {
  const TogetherTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final lang = ref.watch(settingsProvider.select((s) => s.puzzleLang));
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final enabled = ref.watch(multiplayerEnabledProvider);
    final trophies = ref.watch(metaTrophiesProvider);
    final league = (uiLang == 'he' ? Trophies.leaguesHe : Trophies.leaguesEn)[Trophies.leagueIndex(trophies)];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.togetherTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.military_tech_rounded, size: 40, color: enabled ? const Color(0xFFE0B64A) : theme.colorScheme.outline),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l10n.trophies}: $trophies', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(enabled ? l10n.leagueLabel(league) : l10n.multiplayerUnavailable, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ActionCard(
            icon: Icons.sports_kabaddi_rounded,
            title: l10n.togetherVersus,
            subtitle: l10n.versusFindBody,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/together/versus'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.handshake_outlined,
            title: l10n.togetherCoop,
            subtitle: l10n.coopCreateBody,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/together/coop'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.military_tech_outlined,
            title: l10n.trophyLeaderboardTitle,
            subtitle: l10n.leagueLabel(league),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/together/trophies'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.leaderboard_rounded,
            title: l10n.leaderboardTitle,
            subtitle: '${l10n.dailyHardTitle} · $today',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/leaderboard/$today?lang=$lang'),
          ),
        ],
      ),
    );
  }
}
