import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../settings/settings_controller.dart';

/// "Play Together" tab (UX §3/§7): versus and co-op are placeholders for now;
/// the hard-daily leaderboard is live when cloud sync is on.
class TogetherTab extends ConsumerWidget {
  const TogetherTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final lang = ref.watch(settingsProvider.select((s) => s.puzzleLang));
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
                  Icon(Icons.groups_rounded, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(child: Text(l10n.togetherSoon, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ActionCard(
            icon: Icons.leaderboard_rounded,
            title: l10n.leaderboardTitle,
            subtitle: '${l10n.dailyHardTitle} · $today',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/leaderboard/$today?lang=$lang'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.sports_kabaddi_rounded,
            title: l10n.togetherVersus,
            subtitle: l10n.comingSoonShort,
            trailing: Chip(label: Text(l10n.comingSoonShort), visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.handshake_outlined,
            title: l10n.togetherCoop,
            subtitle: l10n.comingSoonShort,
            trailing: Chip(label: Text(l10n.comingSoonShort), visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: Text(l10n.inviteCode),
              subtitle: Text(l10n.comingSoonShort),
              trailing: IconButton(onPressed: null, icon: const Icon(Icons.copy_rounded)),
            ),
          ),
        ],
      ),
    );
  }
}
