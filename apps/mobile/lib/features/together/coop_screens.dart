import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import '../home/home_shell.dart' show pickRandomPuzzle;
import '../packs/packs_providers.dart';
import '../profile/profile_controller.dart';
import '../settings/settings_controller.dart';
import 'multiplayer_providers.dart';
import 'versus_screens.dart' show showJoinCodeDialog;
import 'versus_widgets.dart';

/// Co-op hub: create a room (pick a puzzle by level) or join one by code.
class CoopScreen extends ConsumerStatefulWidget {
  const CoopScreen({super.key});

  @override
  ConsumerState<CoopScreen> createState() => _CoopScreenState();
}

class _CoopScreenState extends ConsumerState<CoopScreen> {
  bool _busy = false;

  Future<void> _create() async {
    final l10n = context.l10n;
    final level = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(alignment: AlignmentDirectional.centerStart, child: Text(l10n.coopPickPuzzle, style: Theme.of(ctx).textTheme.titleLarge)),
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
    if (level == null || !mounted) return;
    // The catalogue may not have been read yet (Home's shelves are lazy).
    await ref.read(packsProvider.future);
    if (!mounted) return;
    final puzzleId = pickRandomPuzzle(ref, level, includeCompleted: true);
    if (puzzleId == null) {
      showSnack(context, l10n.noPuzzleAvailable);
      return;
    }
    setState(() => _busy = true);
    try {
      final lang = ref.read(settingsProvider).puzzleLang;
      final room = await ref.read(multiplayerServiceProvider).createCoopRoom(lang: lang, puzzleId: puzzleId);
      if (mounted) unawaited(context.push('/together/room/${room.id}'));
    } catch (e) {
      if (mounted) showSnack(context, l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = await showJoinCodeDialog(context, title: context.l10n.coopJoin);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final room = await ref.read(multiplayerServiceProvider).joinCoopRoom(code);
      if (mounted) unawaited(context.push('/together/room/${room.id}'));
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.togetherCoop)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.multiplayerUnavailable, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ActionCard(
            icon: Icons.add_home_work_outlined,
            title: l10n.coopCreate,
            subtitle: l10n.coopCreateBody,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: enabled && !_busy ? _create : null,
          ),
          const SizedBox(height: 10),
          ActionCard(
            icon: Icons.qr_code_2_rounded,
            title: l10n.coopJoin,
            subtitle: l10n.enterCode,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: enabled && !_busy ? _join : null,
          ),
        ],
      ),
    );
  }
}

/// Room lobby: up to four coloured avatars, the room code, host start.
class RoomLobbyScreen extends ConsumerStatefulWidget {
  const RoomLobbyScreen({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends ConsumerState<RoomLobbyScreen> {
  bool _navigated = false;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await ref.read(multiplayerServiceProvider).startCoopRoom(widget.roomId);
    } catch (e) {
      if (mounted) showSnack(context, context.l10n.matchFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    try {
      await ref.read(multiplayerServiceProvider).leaveCoopRoom(widget.roomId);
    } catch (_) {}
    if (mounted) context.go('/together');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final uid = ref.watch(multiplayerServiceProvider).uid;
    final async = ref.watch(roomStreamProvider(widget.roomId));
    final room = async.value;
    final myName = ref.watch(profileProvider).displayName ?? l10n.defaultDisplayName;

    if (room != null && room.isRunning && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/play/${room.puzzleId}?room=${room.id}');
      });
    }
    final isHost = room != null && room.hostUid == uid;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: _leave),
          title: Text(l10n.coopRoom),
        ),
        body: room == null
            ? Center(child: async.isLoading ? const CircularProgressIndicator() : Text(l10n.matchFailed))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        runSpacing: 12,
                        children: [
                          for (final e in room.orderedMembers)
                            LobbyAvatar(
                              name: e.key == uid ? myName : e.value.displayName,
                              isMe: e.key == uid,
                              color: coopColor(e.value.color),
                              subtitle: e.key == room.hostUid ? l10n.coopHost : null,
                            ),
                          for (var i = room.members.length; i < 4; i++)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.outline, width: 2)),
                                  child: Icon(Icons.person_add_alt_1_outlined, color: theme.colorScheme.outline),
                                ),
                                const SizedBox(height: 6),
                                Text('·', style: theme.textTheme.bodyMedium),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(l10n.coopMembers(room.members.length), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (room.code != null) InviteCodeCard(code: room.code!, title: l10n.coopCode, shareText: l10n.coopShareText(room.code!)),
                  const SizedBox(height: 16),
                  if (isHost)
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.versusStart),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 10),
                        Text(l10n.coopWaitingHost, style: theme.textTheme.bodyLarge),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

