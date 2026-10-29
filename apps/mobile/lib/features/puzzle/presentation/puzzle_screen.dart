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
import '../../../core/util/clock.dart';
import '../../../core/widgets/common.dart';
import '../../onboarding/tutorial_overlay.dart';
import '../../settings/settings_controller.dart';
import '../../store/store_providers.dart';
import '../../wallet/not_enough_coins_sheet.dart';
import '../../wallet/wallet_controller.dart';
import '../application/puzzle_controller.dart';
import '../application/puzzle_session.dart';
import 'clue_bar.dart';
import 'grid/puzzle_grid.dart';
import 'keyboard/puzzle_keyboard.dart';
import 'sheets/cell_sheets.dart';
import 'sheets/completion_sheet.dart';
import 'sheets/hint_sheet.dart';

/// The solving screen: top bar, zoomable grid, clue bar and custom keyboard.
/// The grid, clue bar and keyboard follow the puzzle language's direction;
/// the chrome follows the UI locale.
class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({super.key, required this.puzzleId});

  final String puzzleId;

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen> with WidgetsBindingObserver {
  final TransformationController _zoom = TransformationController();
  int? _lastFeedbackSeq;
  bool _completionShown = false;
  bool _hintBusy = false;

  PuzzleController get _controller => ref.read(puzzleSessionProvider(widget.puzzleId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.exists(puzzleSessionProvider(widget.puzzleId))) return;
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
        if (!_completionShown) {
          _completionShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showCompletion(s));
        }
    }
  }

  String _title(PuzzleSession s, AppLocalizations l10n) {
    final p = s.puzzle;
    if (s.isTutorial) return l10n.tutorialTitle;
    if (p.daily != null) return '${l10n.dailyVariantName(p.daily!.variant)} · ${p.daily!.date}';
    if (p.pack != null) return '${l10n.levelName(p.level)} · ${l10n.puzzleNumber(p.pack!.index)}';
    return p.title ?? l10n.appTitle;
  }

  Future<void> _showCompletion(PuzzleSession s) async {
    if (!mounted || s.completion == null) return;
    final controller = _controller;
    final nextId = await controller.nextPuzzleId();
    if (!mounted) return;
    final action = await showCompletionSheet(
      context,
      session: s,
      summary: s.completion!,
      hasNext: nextId != null,
      title: _title(s, context.l10n),
    );
    if (!mounted || action == null) return;
    // The only interstitial placement: leaving the completion screen.
    await controller.showCompletionInterstitial(adsFree: ref.read(adsFreeProvider));
    if (!mounted) return;
    switch (action) {
      case CompletionAction.next:
        context.go('/play/$nextId');
      case CompletionAction.home:
        context.go('/');
    }
  }

  Future<void> _onHint() async {
    if (_hintBusy) return;
    final s = ref.read(puzzleSessionProvider(widget.puzzleId)).value;
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
    final s = ref.read(puzzleSessionProvider(widget.puzzleId)).value;
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
        final sel = ref.read(puzzleSessionProvider(widget.puzzleId)).value?.selection;
        if (sel != null) controller.clearWord(sel.wordId);
    }
  }

  Future<void> _onClueCellTap(ClueCell cell) async {
    final s = ref.read(puzzleSessionProvider(widget.puzzleId)).value;
    if (s == null) return;
    if (cell.slots.length == 1) {
      _controller.selectWord(cell.slots.single.wordId);
      return;
    }
    final wordId = await showClueCellSheet(context, session: s, cell: cell);
    if (wordId != null && mounted) _controller.selectWord(wordId);
  }

  Future<void> _onChooseMode() async {
    final s = ref.read(puzzleSessionProvider(widget.puzzleId)).value;
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
    ref.listen(puzzleSessionProvider(widget.puzzleId), (prev, next) {
      final s = next.value;
      final fb = s?.feedback;
      if (s == null || fb == null || fb.seq == _lastFeedbackSeq) return;
      _lastFeedbackSeq = fb.seq;
      _handleFeedback(fb, s);
    });
    final async = ref.watch(puzzleSessionProvider(widget.puzzleId));
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
            onPressed: () => ref.invalidate(puzzleSessionProvider(widget.puzzleId)),
            child: Text(l10n.retry),
          ),
        ),
      ),
      data: (session) {
        final dir = puzzleTextDirection(session.lang);
        final layout = settings.keyboardLayoutFor(session.lang);
        final controller = ref.read(puzzleSessionProvider(widget.puzzleId).notifier);
        final isHebrew = session.lang.code == 'he';
        return Scaffold(
          appBar: AppBar(
            title: Text(_title(session, l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (settings.showTimer) _TimerText(elapsed: controller.elapsedMs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: CoinChip(balance: balance, compact: true, onTap: () => context.push('/store')),
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
                ],
              ),
            ],
          ),
          body: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Directionality(
                          textDirection: dir,
                          child: PuzzleGrid(
                            puzzleId: widget.puzzleId,
                            session: session,
                            zoomController: _zoom,
                            onClueCellTap: _onClueCellTap,
                            onCellLongPress: _onCellLongPress,
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
                  ),
                ),
                Directionality(
                  textDirection: dir,
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SafeArea(
                      top: false,
                      child: PuzzleKeyboard(
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
