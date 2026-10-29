import 'dart:async';
import 'dart:math' as math;

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/manifests.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../meta/game_events_controller.dart';
import '../meta/missions_section.dart';
import '../packs/packs_providers.dart';
import '../packs/progression.dart';
import '../puzzle/application/progress_providers.dart';
import '../puzzle/data/progress_repository.dart';
import '../settings/settings_controller.dart';
import '../wallet/wallet_controller.dart';

/// Bottom bar (UX §3): Play · Daily · Together · Me. Labels always visible.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: l10n.tabPlay),
          NavigationDestination(icon: const Icon(Icons.today_outlined), selectedIcon: const Icon(Icons.today_rounded), label: l10n.tabDaily),
          NavigationDestination(icon: const Icon(Icons.groups_outlined), selectedIcon: const Icon(Icons.groups_rounded), label: l10n.tabTogether),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: l10n.tabMe),
        ],
      ),
    );
  }
}

/// Home (UX §3/§6): continue card → daily cards → missions strip → pack
/// shelves by level → random puzzle → season teaser.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  static bool _loginBonusChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _grantLoginBonus());
  }

  void _grantLoginBonus() {
    if (_loginBonusChecked || !mounted) return;
    _loginBonusChecked = true;
    final today = ref.read(todayProvider);
    final streak = ref.read(streakProvider);
    ref.read(metaProvider.notifier).recordLoginDay(today);
    final granted = ref.read(walletProvider.notifier).grantLoginBonus(date: today, streak: streak);
    if (granted) {
      ref.read(dailyHistoryProvider.notifier).setLoginDate(today);
      final ledger = ref.read(walletProvider);
      final amount = ledger.entries.last.amount;
      showSnack(context, context.l10n.loginBonus(amount));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final balance = ref.watch(balanceProvider);
    final settings = ref.watch(settingsProvider);
    final streak = ref.watch(streakProvider);
    final atRisk = ref.watch(streakAtRiskProvider);
    final today = ref.watch(todayProvider);
    final cont = ref.watch(continuePuzzleProvider);
    final hasContent = ref.watch(languageHasContentProvider(settings.puzzleLang)).value ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.arrow_forward_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(l10n.appTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 8),
            child: CoinChip(balance: balance, onTap: () => context.push('/store')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.homeGreeting, style: theme.textTheme.titleLarge)),
              StreakFlame(streak: streak, label: l10n.streakDays(streak)),
            ],
          ),
          if (atRisk)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.streakAtRisk, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
            ),
          const SizedBox(height: 12),
          _PuzzleLanguageSwitcher(current: settings.puzzleLang),
          if (!hasContent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.comingSoon, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          SectionHeader(l10n.continueTitle),
          if (cont != null)
            _ContinueCard(summary: cont)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.continueEmpty, style: theme.textTheme.bodyLarge),
              ),
            ),
          SectionHeader(l10n.dailyTitle, trailing: TextButton(onPressed: () => context.go('/daily'), child: Text(l10n.tabDaily))),
          _DailyCard(date: today, variant: DailyVariant.easy, streak: streak),
          const SizedBox(height: 10),
          _DailyCard(date: today, variant: DailyVariant.hard, streak: streak),
          const MissionsStrip(),
          SectionHeader(l10n.levelsTitle, trailing: TextButton(onPressed: () => context.push('/levels'), child: Text(l10n.allLevels))),
          for (final level in LevelInfo.all) _PackShelf(level: level),
          const SizedBox(height: 8),
          const _RandomPuzzleButton(),
          const SizedBox(height: 12),
          const _SeasonTeaser(),
        ],
      ),
    );
  }
}

/// Streak flame that grows with the streak (3 / 7 / 30 days).
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key, required this.streak, required this.label});
  final int streak;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = streak >= 30 ? 30.0 : (streak >= 7 ? 26.0 : (streak >= 3 ? 22.0 : 18.0));
    final color = streak == 0
        ? theme.colorScheme.outline
        : streak >= 30
            ? const Color(0xFFD64545)
            : streak >= 7
                ? const Color(0xFFE25D5D)
                : const Color(0xFFF28C28);
    return Chip(
      avatar: Icon(Icons.local_fire_department_rounded, color: color, size: size),
      label: Text(label),
    );
  }
}

class _PuzzleLanguageSwitcher extends ConsumerWidget {
  const _PuzzleLanguageSwitcher({required this.current});
  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enHasContent = ref.watch(languageHasContentProvider('en')).value ?? false;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsPuzzleLanguage, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          segments: [
            ButtonSegment(value: 'he', label: Text(l10n.languageHebrew)),
            ButtonSegment(
              value: 'en',
              label: Text(l10n.languageEnglish),
              icon: enHasContent ? null : const Icon(Icons.schedule_rounded, size: 16),
            ),
          ],
          selected: {current},
          onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setPuzzleLang(s.first),
          showSelectedIcon: false,
        ),
        if (!enHasContent)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${l10n.languageEnglish}: ${l10n.comingSoon}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

String summaryTitle(AppLocalizations l10n, ProgressSummary s) {
  if (s.dailyDate != null) return '${l10n.dailyVariantName(s.dailyVariant!)} · ${s.dailyDate}';
  if (s.packIndex != null) return '${l10n.levelName(s.level)} · ${l10n.puzzleNumber(s.packIndex!)}';
  if (s.kind == PuzzleKind.tutorial) return l10n.tutorialTitle;
  return s.puzzleId;
}

/// Continue card with a progress ring (UX §6).
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.summary});
  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fraction = summary.letterCount == 0 ? 0.0 : summary.filledCount / summary.letterCount;
    final percent = (fraction * 100).round();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/play/${summary.puzzleId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Semantics(
                label: l10n.continueProgress(percent),
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(value: fraction, strokeWidth: 5, backgroundColor: theme.colorScheme.surfaceContainerHighest),
                        Text('$percent%', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summaryTitle(l10n, summary), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(l10n.continueSubtitle(summaryTitle(l10n, summary), summary.filledCount, summary.letterCount),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              FilledButton(onPressed: () => context.push('/play/${summary.puzzleId}'), child: Text(l10n.continueTitle)),
            ],
          ),
        ),
      ),
    );
  }
}

String countdownText(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

class _DailyCard extends ConsumerWidget {
  const _DailyCard({required this.date, required this.variant, required this.streak});
  final String date;
  final DailyVariant variant;
  final int streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final idAsync = ref.watch(dailyPuzzleIdProvider((date, variant)));
    final available = ref.watch(dailyAvailableProvider((date, variant))).value ?? false;
    final id = idAsync.value;
    final summary = id == null ? null : ref.watch(progressSummaryProvider(id));
    final history = ref.watch(dailyHistoryProvider);
    final done = history.isCompleted(date, variant) || (summary?.completed ?? false);
    final now = ref.watch(clockProvider).now();
    final status = done
        ? l10n.dailyCompleted
        : (summary?.inProgress ?? false)
            ? l10n.dailyInProgress
            : available
                ? l10n.dailyPlay
                : l10n.dailyUnavailable;
    return ActionCard(
      icon: variant == DailyVariant.easy ? Icons.wb_sunny_outlined : Icons.local_fire_department_outlined,
      title: l10n.dailyVariantName(variant),
      subtitle: '$status · ${l10n.dailyResetIn(countdownText(untilNextDay(now)))}',
      trailing: done
          ? StarsRow(stars: summary?.stars ?? 1)
          : Icon(available ? Icons.chevron_right_rounded : Icons.cloud_off_outlined),
      onTap: id != null && available ? () => context.push('/play/$id') : null,
    );
  }
}

/// Three daily-mission chips with progress; tap opens the full missions sheet.
class MissionsStrip extends ConsumerWidget {
  const MissionsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final set = ref.watch(missionsProvider);
    final meta = ref.watch(metaProvider);
    final lang = ref.watch(settingsProvider.select((s) => s.uiLang));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          l10n.missionsTitle,
          trailing: TextButton(
            onPressed: () => unawaited(showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: MissionsSection(),
                ),
              ),
            )),
            child: Text(l10n.missionsStripHint),
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: set.daily.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final m = set.daily[i];
              final progress = meta.countersFor(m).progressOf(m).clamp(0, m.target);
              final done = progress >= m.target;
              final claimed = meta.isClaimed(m);
              return Semantics(
                label: '${m.title(lang)}, ${l10n.missionProgress(progress, m.target)}',
                button: true,
                child: ExcludeSemantics(
                  child: Material(
                    color: claimed
                        ? theme.colorScheme.secondary.withValues(alpha: 0.14)
                        : done
                            ? theme.colorScheme.primary.withValues(alpha: 0.14)
                            : theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: done && !claimed
                          ? () {
                              if (ref.read(metaProvider.notifier).claim(m)) showSnack(context, l10n.missionReward(m.reward));
                            }
                          : null,
                      child: Container(
                        width: 190,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: Text(m.title(lang), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(child: LinearProgressIndicator(value: m.target == 0 ? 1 : progress / m.target, minHeight: 6, borderRadius: BorderRadius.circular(3))),
                                const SizedBox(width: 6),
                                Text(claimed ? '✓' : (done ? l10n.missionClaim : '$progress/${m.target}'), style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Horizontal shelf of a level's packs.
class _PackShelf extends ConsumerWidget {
  const _PackShelf({required this.level});
  final LevelInfo level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final packs = ref.watch(packsOfLevelProvider(level.level));
    final progressMap = ref.watch(packProgressMapProvider);
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    if (packs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: InkWell(
            onTap: () => context.push('/levels/${level.level}'),
            child: Row(
              children: [
                Expanded(
                  child: Text('${l10n.levelTitle(level.level)} · ${l10n.levelName(level.level)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(l10n.levelGrid(level.cols, level.rows), style: theme.textTheme.bodySmall),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: packs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final pack = packs[i];
              final unlocked = ref.watch(packUnlockedProvider(pack.id));
              final progress = progressMap[pack.id] ?? PackProgress.none;
              return _PackTile(pack: pack, unlocked: unlocked, progress: progress, title: pack.titleFor(uiLang));
            },
          ),
        ),
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack, required this.unlocked, required this.progress, required this.title});
  final PackInfo pack;
  final bool unlocked;
  final PackProgress progress;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fraction = pack.puzzleCount == 0 ? 0.0 : progress.completed / pack.puzzleCount;
    return Semantics(
      button: unlocked,
      label: '$title, ${unlocked ? l10n.packProgress(progress.completed, pack.puzzleCount, progress.stars) : l10n.packLocked}',
      child: ExcludeSemantics(
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: unlocked ? () => context.push('/pack/${pack.id}') : null,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(unlocked ? (pack.pictures ? Icons.image_outlined : Icons.extension_outlined) : Icons.lock_outline_rounded,
                          color: unlocked ? theme.colorScheme.primary : theme.colorScheme.outline),
                      const Spacer(),
                      if (unlocked && progress.completed > 0) ...[
                        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0B64A)),
                        Text('${progress.stars}', style: theme.textTheme.labelMedium),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(unlocked ? '${progress.completed}/${pack.puzzleCount}' : l10n.packLocked,
                      style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: fraction, minHeight: 5, borderRadius: BorderRadius.circular(3)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Random puzzle": pick a level in a sheet, open an unfinished puzzle of an
/// unlocked pack of that level.
class _RandomPuzzleButton extends ConsumerWidget {
  const _RandomPuzzleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return FilledButton.tonalIcon(
      onPressed: () async {
        final level = await showModalBottomSheet<int>(
          context: context,
          builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: Text(l10n.chooseLevel, style: Theme.of(ctx).textTheme.titleLarge)),
                  ),
                  for (final lv in LevelInfo.all)
                    ListTile(
                      leading: const Icon(Icons.layers_outlined),
                      title: Text('${l10n.levelTitle(lv.level)} · ${l10n.levelName(lv.level)}'),
                      subtitle: Text(l10n.levelGrid(lv.cols, lv.rows)),
                      onTap: () => Navigator.of(ctx).pop(lv.level),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
        if (level == null || !context.mounted) return;
        final id = pickRandomPuzzle(ref, level);
        if (id == null) {
          showSnack(context, l10n.noPuzzleAvailable);
        } else {
          unawaited(context.push('/play/$id'));
        }
      },
      icon: const Icon(Icons.shuffle_rounded),
      label: Text(l10n.randomPuzzle),
    );
  }
}

/// An unfinished puzzle from an unlocked pack of [level], or null.
String? pickRandomPuzzle(WidgetRef ref, int level, {math.Random? random}) {
  final packs = ref.read(packsOfLevelProvider(level));
  final summaries = ref.read(progressSummariesProvider);
  final candidates = <String>[];
  for (final p in packs) {
    if (!ref.read(packUnlockedProvider(p.id))) continue;
    for (final e in p.puzzles) {
      if (!(summaries[e.id]?.completed ?? false)) candidates.add(e.id);
    }
  }
  if (candidates.isEmpty) return null;
  return candidates[(random ?? math.Random()).nextInt(candidates.length)];
}

/// Season pass teaser (placeholder until the season system lands): points
/// derive from completed puzzles so the track moves.
class _SeasonTeaser extends ConsumerWidget {
  const _SeasonTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final stats = ref.watch(playerStatsProvider);
    final points = stats.puzzlesCompleted * 10 + stats.dailiesCompleted * 15;
    const tierSize = 100;
    final tier = points ~/ tierSize + 1;
    final into = points % tierSize;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.military_tech_outlined, color: theme.colorScheme.tertiary, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l10n.seasonTier(tier)} · ${l10n.comingSoonShort}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: into / tierSize, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                  const SizedBox(height: 4),
                  Text(l10n.seasonTeaser(tierSize - into), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
