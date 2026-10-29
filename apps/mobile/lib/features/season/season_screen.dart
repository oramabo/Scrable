import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../meta/game_events_controller.dart';

/// Free season pass: 30 tiers × 100 points, horizontal track, claimable
/// rewards (`earn_season`, idempotent per `season:<id>:tier:<n>`).
class SeasonScreen extends ConsumerStatefulWidget {
  const SeasonScreen({super.key});

  @override
  ConsumerState<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends ConsumerState<SeasonScreen> {
  final ScrollController _track = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _track.dispose();
    super.dispose();
  }

  void _scrollToCurrent(int tier) {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_track.hasClients) return;
      final target = ((tier - 1) * _SeasonTierCard.width - 40).clamp(0.0, _track.position.maxScrollExtent);
      _track.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final info = ref.watch(seasonInfoProvider);
    final points = ref.watch(seasonPointsProvider);
    final meta = ref.watch(metaProvider);
    final reached = SeasonPass.tierFor(points);
    final tiers = SeasonPass.tiers;
    final nextTier = reached < SeasonPass.tierCount ? tiers[reached] : null;
    final claimable = [for (final t in tiers) if (t.index <= reached && !meta.isTierClaimed(info.id, t.index)) t.index];
    _scrollToCurrent(reached + 1);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.seasonPassTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.military_tech_rounded, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.seasonNumber(info.number), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(info.started ? l10n.seasonDaysLeft(info.daysLeft) : l10n.seasonStartsIn(info.startsIn), style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 6),
                          Text('${l10n.seasonPoints(points)} · ${l10n.seasonTier(reached)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                          if (nextTier != null) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (points - (nextTier.points - SeasonPass.pointsPerTier)) / SeasonPass.pointsPerTier,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            const SizedBox(height: 4),
                            Text(l10n.seasonTeaser(nextTier.points - points), style: theme.textTheme.bodySmall),
                          ] else
                            Text(l10n.seasonAllClaimed, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (claimable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: FilledButton.icon(
                onPressed: () {
                  var total = 0;
                  for (final t in claimable) {
                    total += ref.read(metaProvider.notifier).claimSeasonTier(info.id, t);
                  }
                  if (total > 0) showSnack(context, l10n.seasonClaimedToast(total), icon: Icons.monetization_on_rounded);
                },
                icon: const Icon(Icons.redeem_rounded),
                label: Text('${l10n.missionClaim} (${claimable.length})'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SectionHeader(l10n.seasonTier(reached + 1 > SeasonPass.tierCount ? SeasonPass.tierCount : reached + 1)),
          ),
          SizedBox(
            height: 196,
            child: ListView.builder(
              controller: _track,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tiers.length,
              itemBuilder: (context, i) {
                final t = tiers[i];
                final claimed = meta.isTierClaimed(info.id, t.index);
                final unlocked = t.index <= reached;
                return _SeasonTierCard(
                  tier: t,
                  state: claimed ? _TierState.claimed : (unlocked ? _TierState.claimable : _TierState.locked),
                  isNext: t.index == reached + 1,
                  onClaim: () {
                    final coins = ref.read(metaProvider.notifier).claimSeasonTier(info.id, t.index);
                    if (coins > 0) showSnack(context, l10n.seasonClaimedToast(coins), icon: Icons.monetization_on_rounded);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(l10n.seasonHowToEarn, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

enum _TierState { locked, claimable, claimed }

class _SeasonTierCard extends StatelessWidget {
  const _SeasonTierCard({required this.tier, required this.state, required this.isNext, required this.onClaim});
  final SeasonTier tier;
  final _TierState state;
  final bool isNext;
  final VoidCallback onClaim;

  static const width = 124.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final milestone = tier.badge != null;
    final color = switch (state) {
      _TierState.claimed => theme.colorScheme.secondary.withValues(alpha: 0.14),
      _TierState.claimable => theme.colorScheme.primary.withValues(alpha: 0.16),
      _TierState.locked => theme.colorScheme.surfaceContainer,
    };
    final statusText = switch (state) {
      _TierState.claimed => l10n.seasonClaimed,
      _TierState.claimable => l10n.missionClaim,
      _TierState.locked => l10n.seasonLocked,
    };
    return Semantics(
      label: '${l10n.seasonTier(tier.index)}, ${l10n.coinsBalance(tier.coins)}, $statusText',
      button: state == _TierState.claimable,
      child: ExcludeSemantics(
        child: Container(
          width: width - 10,
          margin: const EdgeInsetsDirectional.only(end: 10),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: state == _TierState.claimable ? onClaim : null,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: isNext ? BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.primary, width: 2)) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${tier.index}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Icon(
                          switch (state) {
                            _TierState.claimed => Icons.check_circle_rounded,
                            _TierState.claimable => Icons.redeem_rounded,
                            _TierState.locked => Icons.lock_outline_rounded,
                          },
                          size: 20,
                          color: state == _TierState.locked ? theme.colorScheme.outline : theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (milestone)
                      Icon(Icons.workspace_premium_rounded, color: const Color(0xFFE0B64A), size: 34)
                    else
                      const Icon(Icons.monetization_on_rounded, color: Color(0xFFE0B64A), size: 28),
                    const SizedBox(height: 4),
                    Text(l10n.coinsBalance(tier.coins), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (milestone) Text(l10n.seasonMilestone, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(l10n.seasonPoints(tier.points), style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(statusText, style: theme.textTheme.labelMedium?.copyWith(color: state == _TierState.locked ? theme.colorScheme.outline : theme.colorScheme.primary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
