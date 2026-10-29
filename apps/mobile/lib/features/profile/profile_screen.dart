import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../meta/game_events_controller.dart';
import '../settings/settings_controller.dart';
import 'profile_controller.dart';
import 'profile_model.dart';

/// Avatar disc used across the app.
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.avatar, this.size = 64, this.selected = false});
  final Avatar avatar;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatar.color,
        shape: BoxShape.circle,
        border: selected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
      ),
      child: Icon(avatar.icon, color: Colors.white, size: size * 0.55),
    );
  }
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(labelText: l10n.displayName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(l10n.save)),
        ],
      ),
    );
    if (result != null) ref.read(profileProvider.notifier).setDisplayName(result);
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref, String current, String lang) async {
    final l10n = context.l10n;
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Text(l10n.chooseAvatar, style: Theme.of(ctx).textTheme.titleLarge)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in Avatars.all)
                    Semantics(
                      button: true,
                      selected: a.id == current,
                      label: a.name(lang),
                      child: ExcludeSemantics(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: () => Navigator.of(ctx).pop(a.id),
                          child: AvatarView(avatar: a, size: 56, selected: a.id == current),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (id != null) ref.read(profileProvider.notifier).setAvatar(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);
    final stats = ref.watch(playerStatsProvider);
    final lang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final rank = ref.watch(rankProvider);
    final nextRank = Ranks.next(rank);
    final cloud = ref.watch(cloudSyncProvider);
    final firebaseFlag = ref.watch(appConfigProvider).firebaseEnabled;
    final unlocked = AchievementEngine.unlocked(stats).length;
    final name = profile.displayName ?? l10n.defaultDisplayName;
    final avatar = Avatars.byId(profile.avatarId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabMe),
        actions: [
          IconButton(tooltip: l10n.settingsTitle, onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: '${l10n.chooseAvatar}: ${avatar.name(lang)}',
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () => _pickAvatar(context, ref, profile.avatarId, lang),
                    child: AvatarView(avatar: avatar, size: 80),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
                        IconButton(tooltip: l10n.editName, onPressed: () => _editName(context, ref, profile.displayName ?? ''), icon: const Icon(Icons.edit_outlined)),
                      ],
                    ),
                    Text('${l10n.rankLabel}: ${rank.name(lang)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: Ranks.progress(stats.puzzlesCompleted), minHeight: 6, borderRadius: BorderRadius.circular(3)),
                    const SizedBox(height: 4),
                    Text(
                      nextRank == null ? l10n.topRank : l10n.nextRank(nextRank.minPuzzles - stats.puzzlesCompleted, nextRank.name(lang)),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SectionHeader(l10n.lifetimeStats, trailing: TextButton(onPressed: () => context.push('/stats'), child: Text(l10n.statsTitle))),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(icon: Icons.extension_rounded, label: l10n.statsSolved, value: stats.puzzlesCompleted),
              _StatChip(icon: Icons.emoji_events_outlined, label: l10n.statsPerfect, value: stats.perfectPuzzles),
              _StatChip(icon: Icons.today_rounded, label: l10n.statsDailies, value: stats.dailiesCompleted),
              _StatChip(icon: Icons.local_fire_department_rounded, label: l10n.bestStreak(stats.bestStreak), value: stats.bestStreak),
              _StatChip(icon: Icons.menu_book_outlined, label: l10n.statsWords, value: stats.wordsSolved),
              _StatChip(icon: Icons.monetization_on_outlined, label: l10n.statsCoinsEarned, value: stats.coinsEarned),
            ],
          ),
          const SizedBox(height: 16),
          ActionCard(
            icon: Icons.emoji_events_rounded,
            title: l10n.achievementsTitle,
            subtitle: l10n.achievementsUnlocked(unlocked, Achievements.all.length),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/achievements'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.bar_chart_rounded,
            title: l10n.statsTitle,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/stats'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.settings_outlined,
            title: l10n.settingsTitle,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.info_outline_rounded,
            title: l10n.settingsAbout,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/about'),
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: cloud.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            title: l10n.syncRow,
            subtitle: cloud.enabled
                ? '${l10n.syncOn} · ${cloud.userId?.substring(0, cloud.userId!.length.clamp(0, 8)) ?? ''}'
                : (firebaseFlag ? l10n.syncFailed : l10n.syncOff),
            onTap: cloud.enabled ? () => cloud.pushProfile(profile.toJson()) : null,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '$value',
      child: ExcludeSemantics(
        child: Chip(
          avatar: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          label: Text('$label: $value'),
        ),
      ),
    );
  }
}
