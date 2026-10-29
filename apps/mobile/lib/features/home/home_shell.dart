import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../daily/daily_controller.dart';
import '../packs/packs_providers.dart';
import '../puzzle/application/progress_providers.dart';
import '../puzzle/data/progress_repository.dart';
import '../settings/settings_controller.dart';
import '../wallet/wallet_controller.dart';

/// Bottom-navigation shell: home, packs, daily, settings.
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
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l10n.tabHome),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: l10n.tabPacks),
          NavigationDestination(icon: const Icon(Icons.today_outlined), selectedIcon: const Icon(Icons.today_rounded), label: l10n.tabDaily),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings_rounded), label: l10n.tabSettings),
        ],
      ),
    );
  }
}

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
        title: Text(l10n.appTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: l10n.statsTitle, onPressed: () => context.push('/stats'), icon: const Icon(Icons.bar_chart_rounded)),
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 8),
            child: CoinChip(balance: balance, onTap: () => context.push('/store')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.homeGreeting, style: theme.textTheme.titleLarge)),
              Chip(
                avatar: Icon(Icons.local_fire_department_rounded, color: streak > 0 ? const Color(0xFFE0652A) : theme.colorScheme.outline),
                label: Text(l10n.streakDays(streak)),
              ),
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
            ActionCard(
              icon: Icons.play_arrow_rounded,
              title: _summaryTitle(l10n, cont),
              subtitle: l10n.continueSubtitle(_summaryTitle(l10n, cont), cont.filledCount, cont.letterCount),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/play/${cont.puzzleId}'),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.continueEmpty, style: theme.textTheme.bodyLarge),
              ),
            ),
          SectionHeader(l10n.dailyTitle, trailing: TextButton(onPressed: () => context.go('/daily'), child: Text(l10n.tabDaily))),
          _DailyCard(date: today, variant: DailyVariant.easy),
          const SizedBox(height: 10),
          _DailyCard(date: today, variant: DailyVariant.hard),
          SectionHeader(l10n.levelsTitle, trailing: TextButton(onPressed: () => context.go('/packs'), child: Text(l10n.tabPacks))),
          for (final level in LevelInfo.all) ...[
            _LevelCard(level: level),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  String _summaryTitle(AppLocalizations l10n, ProgressSummary s) {
    if (s.dailyDate != null) return '${l10n.dailyVariantName(s.dailyVariant!)} · ${s.dailyDate}';
    if (s.packIndex != null) return '${l10n.levelName(s.level)} · ${l10n.puzzleNumber(s.packIndex!)}';
    return s.puzzleId;
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

class _DailyCard extends ConsumerWidget {
  const _DailyCard({required this.date, required this.variant});
  final String date;
  final DailyVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final idAsync = ref.watch(dailyPuzzleIdProvider((date, variant)));
    final available = ref.watch(dailyAvailableProvider((date, variant))).value ?? false;
    final id = idAsync.value;
    final summary = id == null ? null : ref.watch(progressSummaryProvider(id));
    final history = ref.watch(dailyHistoryProvider);
    final done = history.isCompleted(date, variant) || (summary?.completed ?? false);
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
      subtitle: '$date · $status',
      trailing: done
          ? StarsRow(stars: summary?.stars ?? 1)
          : Icon(available ? Icons.chevron_right_rounded : Icons.cloud_off_outlined),
      onTap: id != null && available ? () => context.push('/play/$id') : null,
    );
  }
}

class _LevelCard extends ConsumerWidget {
  const _LevelCard({required this.level});
  final LevelInfo level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final progress = ref.watch(levelProgressProvider(level.level));
    final packs = ref.watch(packsOfLevelProvider(level.level));
    final total = packs.fold<int>(0, (n, p) => n + p.puzzleCount);
    return ActionCard(
      icon: Icons.layers_outlined,
      title: '${l10n.levelTitle(level.level)} · ${l10n.levelName(level.level)}',
      subtitle: '${l10n.levelGrid(level.cols, level.rows)} · ${l10n.packProgress(progress.completed, total, progress.stars)}',
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/levels/${level.level}'),
    );
  }
}
