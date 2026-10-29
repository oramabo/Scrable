import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/util/clock.dart';
import '../../core/widgets/common.dart';
import 'leaderboard_service.dart';

final leaderboardProvider = FutureProvider.family<LeaderboardPage?, (String, String)>(
  (ref, key) => ref.watch(leaderboardServiceProvider).top(lang: key.$1, date: key.$2, variant: DailyVariant.hard),
);

/// Read-only top-100 for the hard daily plus the player's own rank. Offline
/// or without Firebase it shows a friendly empty state.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key, required this.lang, required this.date});

  final String lang;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final service = ref.watch(leaderboardServiceProvider);
    final page = ref.watch(leaderboardProvider((lang, date)));

    return Scaffold(
      appBar: AppBar(title: Text('${l10n.leaderboardTitle} · $date')),
      body: !service.available
          ? EmptyState(icon: Icons.leaderboard_outlined, message: l10n.leaderboardUnavailable)
          : page.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => EmptyState(icon: Icons.cloud_off_rounded, message: l10n.leaderboardUnavailable),
              data: (p) {
                if (p == null) return EmptyState(icon: Icons.cloud_off_rounded, message: l10n.leaderboardUnavailable);
                if (p.entries.isEmpty) return EmptyState(icon: Icons.leaderboard_outlined, message: l10n.leaderboardEmpty);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (p.me != null)
                      Card(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: _EntryTile(entry: p.me!, highlight: true, youLabel: l10n.leaderboardYou, total: p.total),
                      ),
                    const SizedBox(height: 8),
                    for (final e in p.entries)
                      _EntryTile(entry: e, highlight: e.uid == p.me?.uid, youLabel: e.uid == p.me?.uid ? l10n.leaderboardYou : null),
                  ],
                );
              },
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.highlight, this.youLabel, this.total});
  final LeaderboardEntry entry;
  final bool highlight;
  final String? youLabel;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final rank = entry.rank;
    final name = entry.displayName?.isNotEmpty == true ? entry.displayName! : l10n.defaultDisplayName;
    final medal = switch (rank) {
      1 => const Color(0xFFE0A526),
      2 => const Color(0xFF8E9AAF),
      3 => const Color(0xFFB87333),
      _ => null,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: medal ?? theme.colorScheme.surfaceContainerHighest,
        foregroundColor: medal != null ? Colors.white : theme.colorScheme.onSurface,
        child: Text(rank == null ? '–' : '$rank', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      title: Text(youLabel != null ? '$name · $youLabel' : name,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text([
        if (rank != null) l10n.leaderboardRank(rank),
        if (total != null) l10n.leaderboardOf(total!),
        if (entry.hints > 0) '${l10n.completionHints}: ${entry.hints}',
      ].join(' · ')),
      trailing: Text(formatDuration(entry.elapsedMs), style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}
