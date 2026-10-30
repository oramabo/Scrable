import 'dart:async';
import 'dart:math' as math;

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart' show LevelConfig;
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/manifests.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/util/relative_time.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../meta/game_events_controller.dart';
import '../meta/missions_section.dart';
import '../packs/packs_providers.dart';
import '../packs/progression.dart';
import '../profile/profile_controller.dart';
import '../puzzle/application/progress_providers.dart';
import '../puzzle/data/progress_repository.dart';
import '../random/random_puzzle_flow.dart';
import '../random/random_puzzle_providers.dart';
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

  /// Tests: allow the once-per-launch login bonus to run again.
  @visibleForTesting
  static void debugResetLoginBonus() => _HomeTabState._loginBonusChecked = false;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  static bool _loginBonusChecked = false;
  final GlobalKey _coinKey = GlobalKey();
  final GlobalKey _greetingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _grantLoginBonus());
  }

  /// Daily login bonus: coins fly into the counter, then a one-line toast.
  Future<void> _grantLoginBonus() async {
    if (_loginBonusChecked || !mounted) return;
    _loginBonusChecked = true;
    final today = ref.read(todayProvider);
    final streak = ref.read(streakProvider);
    ref.read(metaProvider.notifier).recordLoginDay(today);
    final granted = ref.read(walletProvider.notifier).grantLoginBonus(date: today, streak: streak);
    if (!granted) return;
    ref.read(dailyHistoryProvider.notifier).setLoginDate(today);
    final amount = ref.read(walletProvider).entries.last.amount;
    final to = centerOf(_coinKey);
    final from = centerOf(_greetingKey);
    if (to != null && from != null && ref.read(uiTimersEnabledProvider)) {
      await flyCoins(context, from: from, to: to, coins: amount);
    }
    if (mounted) showSnack(context, context.l10n.loginBonus(amount), icon: Icons.monetization_on_rounded);
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
    final name = ref.watch(profileProvider.select((p) => p.displayName));
    final greeting = name == null || name.trim().isEmpty ? l10n.homeGreeting : l10n.homeGreetingNamed(name.trim());
    final randoms = ref.watch(randomPuzzlesProvider);

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
            child: KeyedSubtree(key: _coinKey, child: CoinChip(balance: balance, onTap: () => context.push('/store'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(greeting, key: _greetingKey, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
          SectionHeader(l10n.continueTitle),
          if (cont != null) _ContinueCard(summary: cont) else _StartFirstPuzzleCard(lang: settings.puzzleLang),
          SectionHeader(l10n.dailyTitle, trailing: TextButton(onPressed: () => context.go('/daily'), child: Text(l10n.tabDaily))),
          _DailyCard(date: today, variant: DailyVariant.easy, streak: streak),
          const SizedBox(height: 10),
          _DailyCard(date: today, variant: DailyVariant.hard, streak: streak),
          const MissionsStrip(),
          SectionHeader(l10n.levelsTitle, trailing: TextButton(onPressed: () => context.push('/levels'), child: Text(l10n.allLevels))),
          for (final level in LevelInfo.all) _PackShelf(level: level),
          const SizedBox(height: 8),
          const _RandomPuzzleButton(),
          if (randoms.isNotEmpty) ...[
            SectionHeader(l10n.randomSectionTitle),
            for (final r in randoms.take(5)) _RandomPuzzleRow(summary: r),
          ],
          const SizedBox(height: 12),
          const _SeasonTeaser(),
        ],
      ),
    );
  }
}

/// Empty "continue" state (UX §6): one big primary CTA into pack 1 puzzle 1 of
/// the active puzzle language.
class _StartFirstPuzzleCard extends StatelessWidget {
  const _StartFirstPuzzleCard({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final id = '$lang-l1-p01-01';
    return Card(
      color: theme.colorScheme.primary.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.startFirstPuzzleBody, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              onPressed: () => context.push('/play/$id'),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.startFirstPuzzle),
            ),
          ],
        ),
      ),
    );
  }
}

/// A random (practice) puzzle the player opened: level, progress, stars.
class _RandomPuzzleRow extends StatelessWidget {
  const _RandomPuzzleRow({required this.summary});
  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = summary;
    final status = s.completed ? l10n.dailyCompleted : l10n.continueSubtitle(l10n.randomPuzzleTitle(l10n.levelName(s.level)), s.filledCount, s.letterCount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ActionCard(
        icon: Icons.shuffle_rounded,
        title: l10n.randomPuzzleTitle(l10n.levelName(s.level)),
        subtitle: '$status · ${l10n.randomUnranked}',
        trailing: s.completed ? StarsRow(stars: s.stars) : const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/play/${s.puzzleId}'),
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
    final theme = Theme.of(context);
    // One language for the whole app: the interface switches with the
    // catalogue, dailies, tutorial and the random generator.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsLanguage, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          segments: [
            ButtonSegment(value: 'he', label: Text(l10n.languageHebrew)),
            ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
          ],
          selected: {current},
          onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setLanguage(s.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

String summaryTitle(AppLocalizations l10n, ProgressSummary s) {
  if (s.dailyDate != null) return '${l10n.dailyVariantName(s.dailyVariant!)} · ${s.dailyDate}';
  if (s.packIndex != null) return '${l10n.levelName(s.level)} · ${l10n.puzzleNumber(s.packIndex!)}';
  if (s.kind == PuzzleKind.tutorial) return l10n.tutorialTitle;
  if (s.kind == PuzzleKind.practice) return l10n.randomPuzzleTitle(l10n.levelName(s.level));
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

/// Locale-aware countdown ("בעוד 12 שעות" / "in 12 h").
String countdownText(AppLocalizations l10n, Duration d) => relativeDuration(l10n, d);

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
      subtitle: '$status · ${l10n.dailyResetIn(countdownText(l10n, untilNextDay(now)))}',
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
    final grid = level.grid(ref.watch(settingsProvider.select((s) => s.puzzleLang)));
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
                Text(l10n.levelGrid(grid.cols, grid.rows), style: theme.textTheme.bodySmall),
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

/// "Random puzzle": pick a level in a sheet, then build a fresh unranked
/// puzzle on the device from the bundled lexicon (worker isolate).
class _RandomPuzzleButton extends ConsumerWidget {
  const _RandomPuzzleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final available = ref.watch(randomAvailableProvider).value ?? true;
    return FilledButton.tonalIcon(
      onPressed: !available
          ? null
          : () async {
              final level = await showRandomLevelSheet(context, ref.read(settingsProvider).puzzleLang);
              if (level == null || !context.mounted) return;
              final id = await startRandomPuzzle(context, ref, level);
              if (id != null && context.mounted) unawaited(context.push('/play/$id'));
            },
      icon: const Icon(Icons.shuffle_rounded),
      label: Text(l10n.randomPuzzle),
    );
  }
}

/// Level picker for a random puzzle; returns the chosen level.
/// Levels the device can build quickly in [lang], see [LevelConfig.maxDeviceLevel].
Future<int?> showRandomLevelSheet(BuildContext context, String lang) {
  final l10n = context.l10n;
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Text(l10n.chooseLevel, style: Theme.of(ctx).textTheme.titleLarge)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('${l10n.randomEmpty} ${l10n.randomUnranked}', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ),
            ),
            for (final lv in LevelInfo.all)
              if (lv.level <= LevelConfig.maxDeviceLevel(lang))
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: Text('${l10n.levelTitle(lv.level)} · ${l10n.levelName(lv.level)}'),
                  subtitle: Text(l10n.levelGrid(lv.grid(lang).cols, lv.grid(lang).rows)),
                  onTap: () => Navigator.of(ctx).pop(lv.level),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// A pack puzzle of [level] from an unlocked pack (unfinished unless
/// [includeCompleted]), or null. Used to pick a shared puzzle for co-op rooms.
String? pickRandomPuzzle(WidgetRef ref, int level, {math.Random? random, bool includeCompleted = false}) {
  final packs = ref.read(packsOfLevelProvider(level));
  final summaries = ref.read(progressSummariesProvider);
  final candidates = <String>[];
  for (final p in packs) {
    if (!ref.read(packUnlockedProvider(p.id))) continue;
    for (final e in p.puzzles) {
      if (includeCompleted || !(summaries[e.id]?.completed ?? false)) candidates.add(e.id);
    }
  }
  if (candidates.isEmpty) return null;
  return candidates[(random ?? math.Random()).nextInt(candidates.length)];
}

/// Season pass teaser (UX §6): season number, current tier and the points to
/// the next reward; taps open the pass.
class _SeasonTeaser extends ConsumerWidget {
  const _SeasonTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final info = ref.watch(seasonInfoProvider);
    final points = ref.watch(seasonPointsProvider);
    const tierSize = SeasonPass.pointsPerTier;
    final tier = SeasonPass.tierFor(points);
    final into = points - tier * tierSize;
    final done = tier >= SeasonPass.tierCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/season'),
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
                    Text('${l10n.seasonNumber(info.number)} · ${l10n.seasonTier(tier)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: done ? 1 : into / tierSize, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                    const SizedBox(height: 4),
                    Text(done ? l10n.seasonAllClaimed : l10n.seasonTeaser(tierSize - into), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
