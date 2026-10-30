import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/game_config.dart';
import '../../../core/content/content_repository.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/common.dart';
import '../../feedback/feedback_service.dart';
import '../../feedback/feedback_sheet.dart';
import '../../feedback/rating_prompt.dart';
import '../../notifications/notifications_controller.dart';
import '../../onboarding/tutorial_overlay.dart';
import '../../random/random_puzzle_flow.dart';
import '../../settings/settings_controller.dart';
import '../../store/store_providers.dart';
import '../../together/coop_session.dart';
import '../../together/multiplayer_models.dart';
import '../../together/multiplayer_providers.dart';
import '../../together/versus_session.dart';
import '../../together/versus_widgets.dart';
import '../../wallet/not_enough_coins_sheet.dart';
import '../../wallet/wallet_controller.dart';
import '../application/puzzle_controller.dart';
import '../application/puzzle_session.dart';
import 'clue_bar.dart';
import 'grid/puzzle_grid.dart';
import 'keyboard/cycler_key.dart';
import 'keyboard/puzzle_keyboard.dart';
import 'keyboard/system_keyboard_input.dart';
import 'sheets/cell_sheets.dart';
import 'sheets/completion_sheet.dart';
import 'sheets/hint_sheet.dart';

/// The solving screen: top bar, zoomable grid, clue bar and keyboard (the
/// phone's own with the action keys above it, or the in-app one).
/// The grid, clue bar and keyboard follow the puzzle language's direction;
/// the chrome follows the UI locale.
class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({super.key, required this.puzzleId, this.matchId, this.roomId});

  final String puzzleId;

  /// Versus match this solve belongs to (`/play/:id?match=`).
  final String? matchId;

  /// Co-op room this solve belongs to (`/play/:id?room=`).
  final String? roomId;

  /// Session key: puzzle id plus the multiplayer context.
  String get sessionId => matchId != null
      ? SessionKey.versus(puzzleId, matchId!)
      : roomId != null
          ? SessionKey.coop(puzzleId, roomId!)
          : puzzleId;

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> with WidgetsBindingObserver {
  final TransformationController _zoom = TransformationController();
  final GlobalKey _coinKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  final FocusNode _typingFocus = FocusNode(debugLabel: 'system keyboard');
  int? _lastFeedbackSeq;
  bool _completionShown = false;
  bool _hintBusy = false;
  bool _resultsShown = false;
  bool _leaving = false;

  String get _sessionId => widget.sessionId;
  bool get _isVersus => widget.matchId != null;
  bool get _isCoop => widget.roomId != null;
  bool get _isMultiplayer => _isVersus || _isCoop;

  PuzzleController get _controller => ref.read(puzzleSessionProvider(_sessionId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _zoom.dispose();
    _typingFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.exists(puzzleSessionProvider(_sessionId))) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.pause();
      case AppLifecycleState.resumed:
        _controller.resume();
    }
  }

  void _announce(String text) {
    final dir = Directionality.of(context);
    SemanticsService.sendAnnouncement(View.of(context), text, dir).ignore();
  }

  void _handleFeedback(SessionFeedback fb, PuzzleSession s) {
    final l10n = context.l10n;
    switch (fb.kind) {
      case FeedbackKind.wordCorrect:
        _announce(l10n.wordCorrect);
      case FeedbackKind.wordWrong:
        _announce(l10n.wordWrong);
      case FeedbackKind.letterWrong:
        break;
      case FeedbackKind.puzzleHasErrors:
        showSnack(context, l10n.puzzleHasErrors);
        _announce(l10n.puzzleHasErrors);
      case FeedbackKind.puzzleNoErrors:
        showSnack(context, l10n.puzzleNoErrors);
      case FeedbackKind.checkResult:
        final text = l10n.checkFoundErrors(fb.count);
        showSnack(context, text);
        _announce(text);
      case FeedbackKind.letterRevealed:
        _announce(l10n.letterRevealed);
      case FeedbackKind.nothingToUndo:
        showSnack(context, l10n.nothingToUndo, duration: const Duration(seconds: 1));
      case FeedbackKind.undone:
        break;
      case FeedbackKind.puzzleCompleted:
        _announce(l10n.puzzleCompletedAnnouncement(s.completion?.stars ?? 0));
        // Multiplayer: the match / room result sheet takes over (see build).
        if (!_completionShown && !_isMultiplayer) {
          _completionShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _celebrateThenShow(s));
        }
    }
  }

  String _title(PuzzleSession s, AppLocalizations l10n) {
    final p = s.puzzle;
    if (s.isTutorial) return l10n.tutorialTitle;
    if (_isVersus) return l10n.togetherVersus;
    if (_isCoop) return l10n.togetherCoop;
    if (p.daily != null) return '${l10n.dailyVariantName(p.daily!.variant)} · ${p.daily!.date}';
    if (p.pack != null) return '${l10n.levelName(p.level)} · ${l10n.puzzleNumber(p.pack!.index)}';
    if (p.kind == PuzzleKind.practice) return l10n.randomPuzzleTitle(l10n.levelName(p.level));
    return p.title ?? l10n.appTitle;
  }

  /// UX §4: grid flips cell by cell (≤ 900 ms), coins fly into the counter,
  /// then the summary slides up. Reduced motion: straight to the summary.
  Future<void> _celebrateThenShow(PuzzleSession s) async {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final coins = s.completion?.coinsEarned ?? 0;
    if (!reduceMotion && ref.read(uiTimersEnabledProvider)) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      if (coins > 0) await _flyCoins(coins);
      if (!mounted) return;
    }
    await _showCompletion(s);
  }

  /// A few coin icons travel from the grid centre to the coin chip.
  Future<void> _flyCoins(int coins) async {
    final overlay = Overlay.maybeOf(context);
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final coinBox = _coinKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || gridBox == null || coinBox == null) return;
    final from = gridBox.localToGlobal(gridBox.size.center(Offset.zero));
    final to = coinBox.localToGlobal(coinBox.size.center(Offset.zero));
    final count = coins >= 100 ? 8 : (coins >= 40 ? 6 : 4);
    final entry = OverlayEntry(builder: (_) => FlyingCoins(from: from, to: to, count: count));
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    entry.remove();
  }

  /// Feedback form about the active clue, with the ids the review queue needs.
  void _onReportClue(PuzzleSession s) {
    final word = s.activeWord;
    showFeedbackSheet(
      context,
      initialKind: word == null ? ReportKind.bug : ReportKind.clue,
      quote: word == null ? null : s.puzzle.clueTextOf(word.id),
      details: {
        'puzzleId': s.puzzle.id,
        if (word != null) 'wordId': word.id,
        if (word?.clueId != null) 'clueId': word!.clueId,
        if (word != null) 'clueText': s.puzzle.clueTextOf(word.id),
      },
    );
  }

  Future<void> _showCompletion(PuzzleSession s) async {
    if (!mounted || s.completion == null) return;
    final controller = _controller;
    final nextId = await controller.nextPuzzleId();
    if (!mounted) return;
    final isHardDaily = s.puzzle.daily?.variant == DailyVariant.hard;
    final isRandom = s.puzzle.kind == PuzzleKind.practice;
    final action = await showCompletionSheet(
      context,
      session: s,
      summary: s.completion!,
      hasNext: nextId != null,
      title: _title(s, context.l10n),
      onShared: controller.recordShared,
      showLeaderboard: isHardDaily,
      isRandom: isRandom,
    );
    if (!mounted) return;
    // Opt-in to reminders after the second completed daily (UX: ask with a reason).
    final notificationsAsked = ref.read(settingsProvider).notificationsAsked;
    if (s.puzzle.daily != null) await maybeAskForNotifications(context, ref);
    // The store rating dialog, never right after another prompt.
    if (mounted && ref.read(settingsProvider).notificationsAsked == notificationsAsked) await maybeRequestReview(ref);
    if (!mounted || action == null) return;
    if (action == CompletionAction.leaderboard) {
      final d = s.puzzle.daily!;
      context.go('/leaderboard/${d.date}?lang=${s.puzzle.lang}');
      return;
    }
    if (action == CompletionAction.another) {
      final id = await startRandomPuzzle(context, ref, s.puzzle.level, lang: s.puzzle.lang);
      if (id != null && mounted) context.go('/play/$id');
      return;
    }
    // The only interstitial placement: leaving the completion screen.
    await controller.showCompletionInterstitial(adsFree: ref.read(adsFreeProvider));
    if (!mounted) return;
    switch (action) {
      case CompletionAction.next:
        context.go('/play/$nextId');
      case CompletionAction.daily:
        context.go('/daily');
      case CompletionAction.home:
      case CompletionAction.leaderboard:
      case CompletionAction.another:
        context.go('/');
    }
  }

  /// Versus: once the match document is closed, show win / loss / draw.
  Future<void> _showVersusResults(VersusSessionState v) async {
    if (_resultsShown || !mounted) return;
    final m = v.match;
    if (m == null || m.status != MatchStatus.finished) return;
    _resultsShown = true;
    final uid = ref.read(multiplayerServiceProvider).uid;
    final action = await showVersusResultSheet(context, match: m, uid: uid);
    if (!mounted) return;
    switch (action) {
      case VersusResultAction.rematch:
        final created = await createRematch(context, ref, m);
        if (created != null && mounted) context.go('/together/match/$created');
      case VersusResultAction.home:
      case null:
        context.go('/together');
    }
  }

  /// Co-op: the host confirmed completion → everyone sees the rewards.
  Future<void> _showCoopResults(CoopSessionState c) async {
    if (_resultsShown || !mounted) return;
    final r = c.room;
    if (r == null || !r.isFinished) return;
    _resultsShown = true;
    final uid = ref.read(multiplayerServiceProvider).uid;
    await showCoopResultSheet(context, room: r, uid: uid);
    if (mounted) context.go('/together');
  }

  /// Back button in a multiplayer session: confirm, then leave the match /
  /// room (a running match counts as a loss).
  Future<void> _onLeaveRequested() async {
    if (_leaving) return;
    final l10n = context.l10n;
    if (_isVersus) {
      final v = ref.read(versusSessionProvider(_sessionId));
      if (v.closed || v.finished) {
        if (mounted) context.go('/together');
        return;
      }
    }
    if (_isCoop && (ref.read(coopSessionProvider(_sessionId)).finished)) {
      context.go('/together');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isVersus ? l10n.leaveMatchTitle : l10n.togetherCoop),
        content: Text(_isVersus ? l10n.leaveMatchBody : l10n.coopLeaveBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.leave)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _leaving = true;
    _resultsShown = true; // the forfeit result is not shown as a sheet
    if (_isVersus) await ref.read(versusSessionProvider(_sessionId).notifier).leave();
    if (_isCoop) await ref.read(coopSessionProvider(_sessionId).notifier).leave();
    if (mounted) context.go('/together');
  }

  /// Close button / back on a puzzle with nothing underneath it (the
  /// onboarding tutorial, a "next puzzle" jump): go home. Leaving the
  /// tutorial counts as having seen it.
  void _leaveToHome() {
    final s = ref.read(puzzleSessionProvider(_sessionId)).value;
    if (s != null && s.isTutorial) _controller.markTutorialDone();
    context.go('/');
  }

  /// A character from the phone's keyboard. Space switches direction like a
  /// hardware keyboard; a lone apostrophe / geresh applies the geresh.
  void _onSystemCharacter(String ch, {required bool isHebrew}) {
    final controller = _controller;
    if (ch == ' ') {
      controller.toggleDirection();
    } else if (!controller.typeCharacter(ch) && isHebrew && (ch == HebrewProfile.geresh || ch == "'" || ch == '’')) {
      controller.applyGeresh();
    }
  }

  Future<void> _onHint() async {
    if (_hintBusy) return;
    final s = ref.read(puzzleSessionProvider(_sessionId)).value;
    if (s == null || s.isComplete) return;
    final type = await showHintSheet(context, level: s.puzzle.level, mode: s.progress.mode);
    if (type == null || !mounted) return;
    await _applyHint(type);
  }

  Future<void> _applyHint(HintType type) async {
    final l10n = context.l10n;
    final controller = _controller;
    final price = controller.hintPrice(type);
    final free = price == 0 || ref.read(freeHintsLeftProvider) > 0;
    if (!await confirmHint(context, ref, name: hintName(l10n, type), price: price, free: free)) return;
    if (!mounted) return;
    _hintBusy = true;
    try {
      var result = await controller.useHint(type);
      if (!mounted) return;
      if (result.status == HintStatus.insufficientCoins) {
        final retry = await showNotEnoughCoinsSheet(context, ref, needed: result.price);
        if (retry && mounted) result = await controller.useHint(type);
      }
    } finally {
      _hintBusy = false;
    }
  }

  Future<void> _onCellLongPress(int cell) async {
    final s = ref.read(puzzleSessionProvider(_sessionId)).value;
    if (s == null || s.isComplete) return;
    final controller = _controller;
    controller.moveCursor(cell);
    final action = await showCellActionsSheet(
      context,
      session: s,
      cell: cell,
      revealPrice: controller.hintPrice(HintType.revealLetter),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case CellAction.revealLetter:
        await _applyHint(HintType.revealLetter);
      case CellAction.pencilOn:
        controller.setCellPencil(cell, true);
      case CellAction.pencilOff:
        controller.setCellPencil(cell, false);
      case CellAction.clearWord:
        final sel = ref.read(puzzleSessionProvider(_sessionId)).value?.selection;
        if (sel != null) controller.clearWord(sel.wordId);
    }
  }

  Future<void> _onClueCellTap(ClueCell cell) async {
    final s = ref.read(puzzleSessionProvider(_sessionId)).value;
    if (s == null) return;
    if (cell.slots.length == 1) {
      _controller.selectWord(cell.slots.single.wordId);
      return;
    }
    final wordId = await showClueCellSheet(context, session: s, cell: cell);
    if (wordId != null && mounted) _controller.selectWord(wordId);
  }

  Future<void> _onChooseMode() async {
    final s = ref.read(puzzleSessionProvider(_sessionId)).value;
    if (s == null) return;
    final mode = await showModeSheet(context, current: s.progress.mode, enabled: _controller.canChangeMode);
    if (mode != null && mounted) _controller.setMode(mode);
  }

  Future<void> _onPause() async {
    final l10n = context.l10n;
    await _controller.pause();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.paused),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.resume))],
      ),
    );
    if (mounted) _controller.resume();
  }

  void _zoomBy(double factor) {
    final m = _zoom.value.clone();
    final current = m.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.5, 3.0);
    final f = target / current;
    m.scaleByDouble(f, f, 1, 1);
    _zoom.value = m;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final controller = _controller;
    if (key == LogicalKeyboardKey.backspace) {
      controller.backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
      controller.nextWord();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      controller.toggleDirection();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.isNotEmpty && controller.typeCharacter(ch)) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.listen(puzzleSessionProvider(_sessionId), (prev, next) {
      final s = next.value;
      final fb = s?.feedback;
      if (s == null || fb == null || fb.seq == _lastFeedbackSeq) return;
      _lastFeedbackSeq = fb.seq;
      _handleFeedback(fb, s);
    });
    // Tapping a cell or clue brings the phone's keyboard back if it was closed.
    ref.listen(puzzleSessionProvider(_sessionId), (prev, next) {
      final s = next.value;
      final before = prev?.value?.selection;
      if (s == null || s.isComplete || !ref.read(settingsProvider).systemKeyboard) return;
      if (before != null && before.cell == s.selection?.cell && before.wordId == s.selection?.wordId) return;
      SystemKeyboardInput.show(_typingFocus);
    });
    final async = ref.watch(puzzleSessionProvider(_sessionId));
    final settings = ref.watch(settingsProvider);
    final balance = ref.watch(balanceProvider);

    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          message: e is PuzzleCorruptException
              ? l10n.puzzleChecksumFailed
              : e is PuzzleUnavailableException
                  ? l10n.puzzleNotAvailable
                  : l10n.errorGeneric,
          action: FilledButton(
            onPressed: () => ref.invalidate(puzzleSessionProvider(_sessionId)),
            child: Text(l10n.retry),
          ),
        ),
      ),
      data: (session) {
        final dir = puzzleTextDirection(session.lang);
        final layout = settings.keyboardLayoutFor(session.lang);
        final controller = ref.read(puzzleSessionProvider(_sessionId).notifier);
        final isHebrew = session.lang.code == 'he';
        final cyclerCell = controller.cyclerTarget(session);
        final filledFraction = session.progress.letterCount == 0 ? 0.0 : session.progress.filledCount / session.progress.letterCount;
        final uid = _isMultiplayer ? ref.watch(multiplayerServiceProvider).uid : null;
        VersusSessionState? versus;
        CoopSessionState? coop;
        if (_isVersus) {
          final v = ref.watch(versusSessionProvider(_sessionId));
          versus = v;
          if (v.match?.status == MatchStatus.finished && !_resultsShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showVersusResults(v));
          } else if (v.match?.status == MatchStatus.cancelled && !_resultsShown) {
            _resultsShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showSnack(context, l10n.matchCancelled);
              context.go('/together');
            });
          }
        }
        if (_isCoop) {
          final c = ref.watch(coopSessionProvider(_sessionId));
          coop = c;
          if (c.finished && !_resultsShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showCoopResults(c));
          }
        }
        final canPopRoute = Navigator.canPop(context);
        return PopScope(
          canPop: !_isMultiplayer && canPopRoute,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_isMultiplayer) {
              _onLeaveRequested();
            } else {
              _leaveToHome();
            }
          },
          child: Scaffold(
          appBar: AppBar(
            leading: _isMultiplayer
                ? IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: _onLeaveRequested)
                : canPopRoute
                    ? null
                    : IconButton(tooltip: l10n.leavePuzzle, icon: const Icon(Icons.close_rounded), onPressed: _leaveToHome),
            title: Text(_title(session, l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (settings.showTimer)
                _TimerText(elapsed: controller.elapsedMs)
              else
                _ProgressRing(fraction: filledFraction),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: KeyedSubtree(
                  key: _coinKey,
                  child: CoinChip(balance: balance, compact: true, onTap: () => context.push('/store')),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l10n.menu,
                onSelected: (v) {
                  switch (v) {
                    case 'mode':
                      _onChooseMode();
                    case 'pause':
                      _onPause();
                    case 'zoom_in':
                      _zoomBy(1.25);
                    case 'zoom_out':
                      _zoomBy(0.8);
                    case 'report':
                      _onReportClue(session);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'mode',
                    child: ListTile(
                      leading: const Icon(Icons.tune_rounded),
                      title: Text('${l10n.chooseMode}: ${l10n.modeName(session.progress.mode)}'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'pause',
                    enabled: !session.isComplete,
                    child: ListTile(leading: const Icon(Icons.pause_rounded), title: Text(l10n.pause)),
                  ),
                  PopupMenuItem(
                    value: 'zoom_in',
                    child: ListTile(leading: const Icon(Icons.zoom_in_rounded), title: Text(l10n.zoomIn)),
                  ),
                  PopupMenuItem(
                    value: 'zoom_out',
                    child: ListTile(leading: const Icon(Icons.zoom_out_rounded), title: Text(l10n.zoomOut)),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: ListTile(leading: const Icon(Icons.flag_outlined), title: Text(l10n.reportClue)),
                  ),
                ],
              ),
            ],
          ),
          body: Focus(
            // With the phone's keyboard the hidden text field takes focus.
            autofocus: !settings.systemKeyboard,
            onKeyEvent: _onKey,
            child: Column(
              children: [
                if (versus != null) VersusBar(state: versus, uid: uid),
                if (coop != null)
                  CoopBar(
                    state: coop,
                    uid: uid,
                    gridComplete: session.isComplete || session.progress.isFull,
                    onFinish: () => ref.read(coopSessionProvider(_sessionId).notifier).finish(),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        key: _gridKey,
                        child: Directionality(
                          textDirection: dir,
                          child: PuzzleGrid(
                            puzzleId: _sessionId,
                            session: session,
                            zoomController: _zoom,
                            onClueCellTap: _onClueCellTap,
                            onCellLongPress: _onCellLongPress,
                            remoteTints: coop == null
                                ? const {}
                                : {
                                    for (final m in coop.marks.values) m.cell: coopColor(m.color).withValues(alpha: 0.35),
                                  },
                            remoteCursors: coop == null ? const {} : {for (final e in coop.cursorsExcept(uid).entries) e.key: coopColor(e.value)},
                          ),
                        ),
                      ),
                      if (session.isTutorial)
                        Positioned.fill(
                          child: TutorialCoach(session: session, onDone: controller.markTutorialDone),
                        ),
                      if (session.pencilMode)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Chip(
                            avatar: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(l10n.pencilOn),
                            onDeleted: controller.togglePencilMode,
                          ),
                        ),
                    ],
                  ),
                ),
                Directionality(
                  textDirection: dir,
                  child: ClueBar(
                    session: session,
                    onPrev: controller.prevWord,
                    onNext: controller.nextWord,
                    onSwitch: controller.toggleDirection,
                    onCellTap: controller.moveCursor,
                  ),
                ),
                // The A→Z key slides in only when one cell of the word is left (UX §4).
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.bottomCenter,
                  child: cyclerCell != null && !session.isComplete
                      ? Directionality(
                          textDirection: dir,
                          child: Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            child: CyclerKey(
                              label: isHebrew ? 'א→ת' : 'A→Z',
                              cycling: session.isCycling,
                              previewLabel: session.cyclerCell == null ? null : session.displayAt(session.cyclerCell!),
                              onNext: controller.cycleNext,
                              onConfirm: controller.confirmCycler,
                              onCancel: controller.cancelCycler,
                              height: settings.bigKeyboard ? 56 : 48,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
                Directionality(
                  textDirection: dir,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SafeArea(
                      top: false,
                      child: settings.systemKeyboard
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Stack(
                                children: [
                                  SystemKeyboardInput(
                                    focusNode: _typingFocus,
                                    enabled: !session.isComplete,
                                    onCharacter: (ch) => _onSystemCharacter(ch, isHebrew: isHebrew),
                                    onBackspace: controller.backspace,
                                    onSubmit: controller.nextWord,
                                  ),
                                  PuzzleActionRow(
                                    height: settings.bigKeyboard ? 52 : 44,
                                    enabled: !session.isComplete,
                                    onHint: _onHint,
                                    onUndo: controller.undo,
                                    onNextWord: controller.nextWord,
                                    onGeresh: isHebrew ? controller.applyGeresh : null,
                                  ),
                                ],
                              ),
                            )
                          : PuzzleKeyboard(
                              lang: session.lang,
                              layout: layout,
                              big: settings.bigKeyboard,
                              enabled: !session.isComplete,
                              onSymbol: controller.typeSymbol,
                              onBackspace: controller.backspace,
                              onNextWord: controller.nextWord,
                              onHint: _onHint,
                              onUndo: controller.undo,
                              onGeresh: isHebrew ? controller.applyGeresh : null,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

class _TimerText extends StatelessWidget {
  const _TimerText({required this.elapsed});
  final ValueListenable<int> elapsed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: elapsed,
      builder: (context, ms, _) => Semantics(
        label: context.l10n.timer,
        value: formatDuration(ms),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatDuration(ms),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    );
  }
}


/// Positive framing instead of a visible timer: share of letters filled.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).round();
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.progressRing(percent),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  strokeWidth: 3.5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.primary,
                ),
                Text('$percent', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
