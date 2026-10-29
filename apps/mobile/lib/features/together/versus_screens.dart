import 'dart:async';

import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../meta/game_events_controller.dart';
import '../packs/packs_providers.dart';
import '../profile/profile_controller.dart';
import '../settings/settings_controller.dart';
import 'multiplayer_models.dart';
import 'multiplayer_providers.dart';
import 'versus_widgets.dart';

/// Versus hub: find an opponent, invite a friend, join with a code.
class VersusScreen extends ConsumerStatefulWidget {
  const VersusScreen({super.key});

  @override
  ConsumerState<VersusScreen> createState() => _VersusScreenState();
}

class _VersusScreenState extends ConsumerState<VersusScreen> {
  int _level = 1;
  bool _searching = false;
  bool _busy = false;
  StreamSubscription<String?>? _queueSub;

  @override
  void dispose() {
    unawaited(_queueSub?.cancel());
    super.dispose();
  }

  Future<void> _find() async {
    final service = ref.read(multiplayerServiceProvider);
    final lang = ref.read(settingsProvider).puzzleLang;
    setState(() => _busy = true);
    try {
      final r = await service.findMatch(lang: lang, level: _level);
      if (!mounted) return;
      if (!r.queued) {
        unawaited(context.push('/together/match/${r.match!.id}'));
        return;
      }
      setState(() => _searching = true);
      unawaited(_queueSub?.cancel());
      _queueSub = service.watchQueue(lang: lang, level: _level).listen((matchId) {
        if (matchId == null || !mounted) return;
        unawaited(_queueSub?.cancel());
        _queueSub = null;
        setState(() => _searching = false);
        unawaited(context.push('/together/match/$matchId'));
      });
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancelSearch() {
    unawaited(_queueSub?.cancel());
    _queueSub = null;
    setState(() => _searching = false);
  }

  Future<void> _invite() async {
    final service = ref.read(multiplayerServiceProvider);
    final lang = ref.read(settingsProvider).puzzleLang;
    setState(() => _busy = true);
    try {
      final m = await service.createMatch(lang: lang, level: _level);
      if (mounted) unawaited(context.push('/together/match/${m.id}'));
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = await showJoinCodeDialog(context);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final m = await ref.read(multiplayerServiceProvider).joinMatch(code);
      if (mounted) unawaited(context.push('/together/match/${m.id}'));
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final enabled = ref.watch(multiplayerEnabledProvider);
    final trophies = ref.watch(metaProviderTrophies);
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final league = (uiLang == 'he' ? Trophies.leaguesHe : Trophies.leaguesEn)[Trophies.leagueIndex(trophies)];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.togetherVersus)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.military_tech_rounded, color: Color(0xFFE0B64A)),
              title: Text('${l10n.trophies}: $trophies'),
              subtitle: Text(l10n.leagueLabel(league)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/together/trophies'),
            ),
          ),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.multiplayerUnavailable, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          SectionHeader(l10n.chooseLevel),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            segments: [for (final lv in LevelInfo.all) ButtonSegment(value: lv.level, label: Text('${lv.level}'))],
            selected: {_level},
            onSelectionChanged: (v) => setState(() => _level = v.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          if (_searching)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                    const SizedBox(width: 14),
                    Expanded(child: Text(l10n.versusSearching, style: theme.textTheme.titleMedium)),
                    TextButton(onPressed: _cancelSearch, child: Text(l10n.versusCancelSearch)),
                  ],
                ),
              ),
            )
          else
            ActionCard(
              icon: Icons.sports_kabaddi_rounded,
              title: l10n.versusFind,
              subtitle: l10n.versusFindBody,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: enabled && !_busy ? _find : null,
            ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.person_add_alt_1_rounded,
            title: l10n.versusInvite,
            subtitle: l10n.versusInviteBody,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: enabled && !_busy ? _invite : null,
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.qr_code_2_rounded,
            title: l10n.versusJoin,
            subtitle: l10n.enterCode,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: enabled && !_busy ? _join : null,
          ),
        ],
      ),
    );
  }
}

/// Local trophies mirror (server value when synced).
final metaProviderTrophies = Provider<int>((ref) => ref.watch(metaTrophiesProvider));

/// Six-character invite / room code prompt. Returns the normalised code.
Future<String?> showJoinCodeDialog(BuildContext context, {String? title}) =>
    showDialog<String>(context: context, builder: (_) => _JoinCodeDialog(title: title));

class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog({this.title});
  final String? title;

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final c = normalizeInviteCode(_controller.text);
    if (c == null) {
      setState(() => _error = context.l10n.enterCode);
    } else {
      Navigator.of(context).pop(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title ?? l10n.versusJoin),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 7,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Inter', letterSpacing: 4, fontWeight: FontWeight.w700, fontSize: 22),
        decoration: InputDecoration(hintText: l10n.enterCode, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.join)),
      ],
    );
  }
}

/// Lobby of one match: both avatars, invite code (host), start / ready.
/// Navigates into the puzzle once the match is running.
class MatchLobbyScreen extends ConsumerStatefulWidget {
  const MatchLobbyScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<MatchLobbyScreen> createState() => _MatchLobbyScreenState();
}

class _MatchLobbyScreenState extends ConsumerState<MatchLobbyScreen> {
  bool _navigated = false;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(multiplayerServiceProvider).startMatch(widget.matchId);
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(MatchDoc? m) async {
    final service = ref.read(multiplayerServiceProvider);
    try {
      if (m != null && !m.isClosed) {
        if (m.hostUid == service.uid && m.status != MatchStatus.running) {
          await service.cancelMatch(m.id);
        } else {
          await service.leaveMatch(m.id);
        }
      }
    } catch (_) {}
    if (mounted) context.go('/together');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final service = ref.watch(multiplayerServiceProvider);
    final uid = service.uid;
    final async = ref.watch(matchStreamProvider(widget.matchId));
    final m = async.value;
    final profile = ref.watch(profileProvider);
    final myName = profile.displayName ?? l10n.defaultDisplayName;

    if (m != null && m.isRunning && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/play/${m.puzzleId}?match=${m.id}');
      });
    }
    if (m != null && m.status == MatchStatus.cancelled && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSnack(context, l10n.matchCancelled);
        context.go('/together');
      });
    }

    final isHost = m != null && m.hostUid == uid;
    final me = m?.player(uid);
    final opponent = m?.opponent(uid);
    final waitingGuest = m != null && m.status == MatchStatus.waiting;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(m);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _leave(m)),
          title: Text(l10n.versusLobby),
        ),
        body: m == null
            ? Center(child: async.isLoading ? const CircularProgressIndicator() : Text(l10n.matchFailed))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          LobbyAvatar(name: me?.displayName ?? myName, isMe: true, subtitle: isHost ? l10n.coopHost : (me?.ready ?? false ? l10n.versusReady : null)),
                          Text('VS', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary, fontFamily: 'Inter')),
                          if (opponent != null)
                            LobbyAvatar(name: opponent.displayName, isMe: false, subtitle: opponent.ready ? l10n.versusReady : null)
                          else
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.outline, width: 2)),
                                  child: Icon(Icons.person_outline_rounded, color: theme.colorScheme.outline),
                                ),
                                const SizedBox(height: 6),
                                Text(l10n.versusOpponent, style: theme.textTheme.bodyMedium),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${l10n.levelTitle(m.level)} · ${l10n.levelName(m.level)}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (m.inviteCode != null && m.mode == 'invite')
                    InviteCodeCard(code: m.inviteCode!, title: l10n.inviteCode, shareText: l10n.shareInviteText(m.inviteCode!)),
                  const SizedBox(height: 16),
                  if (waitingGuest)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 10),
                        Text(l10n.versusWaitingGuest, style: theme.textTheme.bodyLarge),
                      ],
                    )
                  else if (m.status == MatchStatus.ready)
                    isHost
                        ? FilledButton.icon(
                            onPressed: _busy ? null : _start,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(l10n.versusStart),
                          )
                        : (me?.ready ?? false)
                            ? Text(l10n.versusReadyDone, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge)
                            : FilledButton.icon(
                                onPressed: _busy ? null : _start,
                                icon: const Icon(Icons.check_rounded),
                                label: Text(l10n.versusReady),
                              ),
                ],
              ),
      ),
    );
  }
}

/// Trophy leaderboard of the active puzzle language, grouped by league.
class TrophyLeaderboardScreen extends ConsumerWidget {
  const TrophyLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lang = ref.watch(settingsProvider.select((s) => s.puzzleLang));
    final uiLang = ref.watch(settingsProvider.select((s) => s.uiLang));
    final names = uiLang == 'he' ? Trophies.leaguesHe : Trophies.leaguesEn;
    final async = ref.watch(trophyBoardProvider(lang));
    final uid = ref.watch(multiplayerServiceProvider).uid;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trophyLeaderboardTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyState(icon: Icons.cloud_off_rounded, message: l10n.leaderboardUnavailable),
        data: (board) {
          if (board == null) return EmptyState(icon: Icons.cloud_off_rounded, message: l10n.leaderboardUnavailable);
          if (board.entries.isEmpty) return EmptyState(icon: Icons.military_tech_outlined, message: l10n.leaderboardEmpty);
          final me = board.me;
          int? lastLeague;
          final rows = <Widget>[];
          for (final e in board.entries) {
            final league = Trophies.leagueIndex(e.trophies);
            if (league != lastLeague) {
              lastLeague = league;
              rows.add(SectionHeader(names[league]));
            }
            final mine = e.uid == uid;
            rows.add(Card(
              color: mine ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
              child: ListTile(
                leading: CircleAvatar(child: Text('${e.rank}')),
                title: Text(mine ? '${e.displayName} · ${l10n.leaderboardYou}' : e.displayName),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.military_tech_rounded, color: Color(0xFFE0B64A), size: 20),
                    const SizedBox(width: 4),
                    Text('${e.trophies}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (me != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: Text('${l10n.leaderboardRank(me.rank)} · ${me.trophies} ${l10n.trophies}'),
                    subtitle: Text(l10n.leagueLabel(names[Trophies.leagueIndex(me.trophies)])),
                  ),
                ),
              ...rows,
            ],
          );
        },
      ),
    );
  }
}
