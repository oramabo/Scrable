import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/manifests.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../puzzle/application/progress_providers.dart';
import '../puzzle/data/progress_repository.dart';
import '../settings/settings_controller.dart';
import 'packs_providers.dart';
import 'progression.dart';

/// Packs tab: the five levels.
class LevelsTab extends ConsumerWidget {
  const LevelsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final packs = ref.watch(packsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.levelsTitle)),
      body: packs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, message: l10n.errorGeneric),
        data: (_) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: LevelInfo.all.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final level = LevelInfo.all[i];
            final progress = ref.watch(levelProgressProvider(level.level));
            final levelPacks = ref.watch(packsOfLevelProvider(level.level));
            final total = levelPacks.fold<int>(0, (n, p) => n + p.puzzleCount);
            return ActionCard(
              icon: Icons.layers_outlined,
              title: '${l10n.levelTitle(level.level)} · ${l10n.levelName(level.level)}',
              subtitle: levelPacks.isEmpty
                  ? l10n.noPacksYet
                  : '${l10n.levelGrid(level.cols, level.rows)} · ${l10n.packProgress(progress.completed, total, progress.stars)}',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/levels/${level.level}'),
            );
          },
        ),
      ),
    );
  }
}

class PacksOfLevelScreen extends ConsumerWidget {
  const PacksOfLevelScreen({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final packs = ref.watch(packsOfLevelProvider(level));
    final loading = ref.watch(packsProvider).isLoading;
    final progressMap = ref.watch(packProgressMapProvider);
    final config = ref.watch(gameConfigProvider);
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    return Scaffold(
      appBar: AppBar(title: Text('${l10n.levelTitle(level)} · ${l10n.levelName(level)}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : packs.isEmpty
              ? EmptyState(icon: Icons.inventory_2_outlined, message: l10n.noPacksYet)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: packs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final pack = packs[i];
                    final unlocked = ref.watch(packUnlockedProvider(pack.id));
                    final progress = progressMap[pack.id] ?? PackProgress.none;
                    return ActionCard(
                      icon: unlocked ? Icons.extension_outlined : Icons.lock_outline_rounded,
                      title: pack.titleFor(uiLang),
                      subtitle: unlocked
                          ? l10n.packProgress(progress.completed, pack.puzzleCount, progress.stars)
                          : '${l10n.packLocked} · ${l10n.packUnlockHint(config.packUnlockStars, config.packUnlockCompleted)}',
                      trailing: unlocked
                          ? (progress.completed >= pack.puzzleCount && pack.puzzleCount > 0
                              ? const Icon(Icons.verified_rounded, color: Color(0xFFE0A526))
                              : const Icon(Icons.chevron_right_rounded))
                          : const Icon(Icons.lock_rounded),
                      onTap: unlocked ? () => context.push('/pack/${pack.id}') : null,
                      semanticsLabel: unlocked ? null : l10n.packLocked,
                    );
                  },
                ),
    );
  }
}

/// 30-puzzle grid with progress and stars.
class PackScreen extends ConsumerWidget {
  const PackScreen({super.key, required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pack = ref.watch(packProvider(packId));
    final loading = ref.watch(packsProvider).isLoading;
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final summaries = ref.watch(progressSummariesProvider);
    final theme = Theme.of(context);
    if (pack == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(icon: Icons.error_outline, message: l10n.errorGeneric),
      );
    }
    final progress = PackProgress.fromSummaries(pack, summaries);
    final entries = pack.puzzles.isNotEmpty
        ? pack.puzzles
        : [for (var i = 1; i <= pack.puzzleCount; i++) PackPuzzleEntry(id: '$packId-${i.toString().padLeft(2, '0')}', index: i)];
    return Scaffold(
      appBar: AppBar(title: Text(pack.titleFor(uiLang))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text(l10n.packProgress(progress.completed, pack.puzzleCount, progress.stars), style: theme.textTheme.bodyLarge)),
                Text('${progress.stars}/${pack.puzzleCount * 3}', style: theme.textTheme.titleMedium),
                const Icon(Icons.star_rounded, color: Color(0xFFE0A526)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: pack.puzzleCount == 0 ? 0 : progress.completed / pack.puzzleCount,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final s = summaries[e.id];
                return _PuzzleTile(entry: e, summary: s, onTap: () => context.push('/play/${e.id}'));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleTile extends StatelessWidget {
  const _PuzzleTile({required this.entry, required this.summary, required this.onTap});
  final PackPuzzleEntry entry;
  final ProgressSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final completed = summary?.completed ?? false;
    final started = summary?.started ?? false;
    final stars = summary?.stars ?? 0;
    final color = completed
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : started
            ? theme.colorScheme.secondary.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainer;
    final status = completed
        ? l10n.dailyCompleted
        : started
            ? l10n.dailyInProgress
            : '';
    return Semantics(
      button: true,
      label: '${l10n.puzzleNumber(entry.index)}${status.isEmpty ? '' : ', $status'}${completed ? ', $stars/3' : ''}',
      child: ExcludeSemantics(
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${entry.index}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (completed)
                  StarsRow(stars: stars, size: 14)
                else if (started)
                  Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.secondary)
                else if (entry.words != null)
                  Text(l10n.puzzleWords(entry.words!), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
