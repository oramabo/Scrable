import 'dart:async';

import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/util/relative_time.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_controller.dart';
import 'game_events_controller.dart';

/// Home-screen missions: today's three daily missions (reset at local
/// midnight) and the week's three (Monday reset), with progress, claim
/// buttons and a countdown.
class MissionsSection extends ConsumerStatefulWidget {
  const MissionsSection({super.key});

  @override
  ConsumerState<MissionsSection> createState() => _MissionsSectionState();
}

class _MissionsSectionState extends ConsumerState<MissionsSection> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (ref.read(uiTimersEnabledProvider)) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final set = ref.watch(missionsProvider);
    final now = ref.watch(clockProvider).now();
    final lang = ref.watch(settingsProvider.select((s) => s.uiLang));

    Widget group(String title, List<Mission> missions, Duration left) => Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                    Icon(Icons.schedule_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(l10n.missionResetIn(relativeDuration(l10n, left)), style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                for (final m in missions) _MissionRow(mission: m, lang: lang),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.missionsTitle),
        group(l10n.missionsDaily, set.daily, untilNextDay(now)),
        const SizedBox(height: 10),
        group(l10n.missionsWeekly, set.weekly, untilNextWeek(now)),
      ],
    );
  }
}

class _MissionRow extends ConsumerWidget {
  const _MissionRow({required this.mission, required this.lang});
  final Mission mission;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final meta = ref.watch(metaProvider);
    final progress = meta.countersFor(mission).progressOf(mission).clamp(0, mission.target);
    final done = progress >= mission.target;
    final claimed = meta.isClaimed(mission);
    final title = mission.title(lang);
    final status = claimed ? l10n.missionClaimed : l10n.missionProgress(progress, mission.target);

    return Semantics(
      label: '$title, $status, ${l10n.missionReward(mission.reward)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: mission.target == 0 ? 1 : progress / mission.target,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.missionProgress(progress, mission.target), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (claimed)
                Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
              else if (done)
                FilledButton(
                  onPressed: () {
                    if (ref.read(metaProvider.notifier).claim(mission)) {
                      showSnack(context, l10n.missionReward(mission.reward));
                    }
                  },
                  child: Text('${l10n.missionClaim} +${mission.reward}'),
                )
              else
                Chip(
                  avatar: const Icon(Icons.monetization_on_rounded, size: 16, color: Color(0xFFE0A526)),
                  label: Text('+${mission.reward}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
