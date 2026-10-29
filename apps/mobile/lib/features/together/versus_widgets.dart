import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../../core/util/clock.dart';
import '../../core/widgets/common.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_model.dart';
import '../profile/profile_screen.dart';
import 'coop_session.dart';
import 'multiplayer_models.dart';
import 'multiplayer_providers.dart';
import 'versus_session.dart';

/// Thin dual progress bar under the app bar: me (primary) vs the opponent.
class VersusBar extends StatelessWidget {
  const VersusBar({super.key, required this.state, required this.uid});
  final VersusSessionState state;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final m = state.match;
    final opponent = m?.opponent(uid);
    final me = state.finished ? 1.0 : state.myProgress;
    final them = (opponent?.finished ?? false) ? 1.0 : state.opponentProgress;
    final status = state.finished && !(opponent?.finished ?? false)
        ? l10n.versusFinishedFirst
        : (m?.isRunning ?? false)
            ? l10n.versusRunning
            : '';
    return Semantics(
      label: '${l10n.leaderboardYou} ${(me * 100).round()}%, ${l10n.versusOpponent} ${(them * 100).round()}%',
      child: ExcludeSemantics(
        child: Container(
          color: theme.colorScheme.surfaceContainer,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            children: [
              _ProgressLine(label: l10n.leaderboardYou, value: me, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              _ProgressLine(label: opponent?.displayName ?? l10n.versusOpponent, value: them, color: theme.colorScheme.tertiary),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(status, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 6, color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 36, child: Text('${(value * 100).round()}%', textAlign: TextAlign.end, style: theme.textTheme.labelSmall)),
      ],
    );
  }
}

/// Co-op strip: member avatars with their colours and the host's "we're done".
class CoopBar extends StatelessWidget {
  const CoopBar({super.key, required this.state, required this.uid, required this.gridComplete, required this.onFinish});
  final CoopSessionState state;
  final String? uid;
  final bool gridComplete;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final room = state.room;
    final isHost = room != null && room.hostUid == uid;
    final members = room?.orderedMembers ?? const [];
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          for (final e in members)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Tooltip(
                message: e.value.displayName,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: coopColor(e.value.color),
                  child: Text(
                    e.value.displayName.isEmpty ? '?' : e.value.displayName.characters.first,
                    style: theme.textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Text(
              gridComplete ? l10n.coopGridComplete : l10n.coopPlaying(members.length),
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isHost && !state.finished)
            FilledButton.tonal(
              onPressed: gridComplete && !state.finishing ? onFinish : null,
              child: Text(l10n.coopFinish),
            ),
        ],
      ),
    );
  }
}

enum VersusResultAction { rematch, home }

String signedDelta(int? delta) => delta == null ? '0' : (delta > 0 ? '+$delta' : '$delta');

/// Win / loss / draw with the trophy delta and rewards.
Future<VersusResultAction?> showVersusResultSheet(BuildContext context, {required MatchDoc match, required String? uid}) {
  return showModalBottomSheet<VersusResultAction>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final l10n = ctx.l10n;
      final theme = Theme.of(ctx);
      final me = match.player(uid);
      final opponent = match.opponent(uid);
      final result = me?.result;
      final title = switch (result) {
        MatchResult.win => l10n.versusWin,
        MatchResult.draw => l10n.versusDraw,
        MatchResult.loss => l10n.versusLoss,
        MatchResult.forfeit => l10n.versusLoss,
        null => l10n.versusDraw,
      };
      final subtitle = opponent?.result == MatchResult.forfeit ? l10n.versusForfeit : null;
      final rewards = me?.rewards;
      final uiLang = Localizations.localeOf(ctx).languageCode;
      final league = (uiLang == 'he' ? Trophies.leaguesHe : Trophies.leaguesEn)[Trophies.leagueIndex(me?.trophiesAfter ?? 0)];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                result == MatchResult.win ? Icons.emoji_events_rounded : (result == MatchResult.draw ? Icons.handshake_rounded : Icons.sentiment_neutral_rounded),
                size: 56,
                color: result == MatchResult.win ? const Color(0xFFE0B64A) : theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _ResultStat(icon: Icons.military_tech_rounded, label: l10n.trophies, value: l10n.trophyDelta(signedDelta(me?.trophyDelta)))),
                  Expanded(child: _ResultStat(icon: Icons.timer_outlined, label: l10n.completionTime, value: formatDuration(me?.elapsedMs ?? 0))),
                  Expanded(child: _ResultStat(icon: Icons.person_outline_rounded, label: opponent?.displayName ?? l10n.versusOpponent, value: formatDuration(opponent?.elapsedMs ?? 0))),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.leagueLabel(league), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              if (rewards != null && rewards.credited) ...[
                const SizedBox(height: 8),
                Text(l10n.versusRewards(rewards.coins, rewards.xp), textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(VersusResultAction.rematch),
                icon: const Icon(Icons.replay_rounded),
                label: Text(l10n.rematch),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(VersusResultAction.home),
                icon: const Icon(Icons.groups_rounded),
                label: Text(l10n.togetherTitle),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ResultStat extends StatelessWidget {
  const _ResultStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      value: value,
      child: ExcludeSemantics(
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(value, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Rematch: a fresh invite-code match at the same level, to share with the
/// same opponent. Returns the new match id.
Future<String?> createRematch(BuildContext context, WidgetRef ref, MatchDoc previous) async {
  try {
    final m = await ref.read(multiplayerServiceProvider).createMatch(lang: previous.lang, level: previous.level);
    return m.id;
  } catch (e) {
    if (context.mounted) showSnack(context, context.l10n.matchFailed);
    return null;
  }
}

/// Co-op rewards for everyone once the host confirmed.
Future<void> showCoopResultSheet(BuildContext context, {required CoopRoomDoc room, required String? uid}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final l10n = ctx.l10n;
      final theme = Theme.of(ctx);
      final mine = room.members[uid]?.rewards;
      final rewarded = room.members.values.any((m) => m.rewards?.credited ?? false);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.handshake_rounded, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(room.solved ? l10n.coopFinished : l10n.matchCancelled, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                children: [
                  for (final e in room.orderedMembers)
                    Chip(
                      avatar: CircleAvatar(backgroundColor: coopColor(e.value.color), radius: 10),
                      label: Text(e.value.displayName),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                rewarded ? l10n.coopRewards(mine?.coins ?? 25, mine?.xp ?? 30) : l10n.coopNoReward,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.groups_rounded),
                label: Text(l10n.togetherTitle),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Invite / room code with copy + share.
class InviteCodeCard extends ConsumerWidget {
  const InviteCodeCard({super.key, required this.code, required this.title, required this.shareText});
  final String code;
  final String title;
  final String shareText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  Text(code, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4, fontFamily: 'Inter')),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.codeCopied,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) showSnack(context, l10n.codeCopied, icon: Icons.check_rounded);
              },
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              tooltip: l10n.share,
              onPressed: () => SharePlus.instance.share(ShareParams(text: shareText)).ignore(),
              icon: const Icon(Icons.share_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// A player's avatar in a lobby: the local player's chosen avatar, a letter
/// disc for everybody else.
class LobbyAvatar extends ConsumerWidget {
  const LobbyAvatar({super.key, required this.name, required this.isMe, this.color, this.size = 56, this.subtitle});
  final String name;
  final bool isMe;
  final Color? color;
  final double size;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final Widget disc;
    if (isMe) {
      disc = AvatarView(avatar: Avatars.byId(ref.watch(profileProvider.select((p) => p.avatarId))), size: size);
    } else {
      disc = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color ?? theme.colorScheme.tertiary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(name.isEmpty ? '?' : name.characters.first, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        disc,
        const SizedBox(height: 6),
        SizedBox(width: size + 36, child: Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        if (subtitle != null) Text(subtitle!, style: theme.textTheme.labelSmall, maxLines: 1),
      ],
    );
  }
}
