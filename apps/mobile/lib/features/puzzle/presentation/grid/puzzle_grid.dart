import 'dart:math' as math;

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/puzzle_controller.dart';
import '../../application/puzzle_session.dart';
import 'grid_geometry.dart';
import 'grid_painter.dart';

/// Zoomable, pannable grid. Cells are at least 44 dp: the grid fills the
/// width when that allows ≥ 44 dp cells, otherwise cells are 44 dp and the
/// view pans to keep the active cell visible. A transparent semantics overlay
/// gives every cell a label and tap action.
class PuzzleGrid extends ConsumerStatefulWidget {
  const PuzzleGrid({
    super.key,
    required this.puzzleId,
    required this.session,
    required this.onClueCellTap,
    required this.onCellLongPress,
    this.zoomController,
  });

  final String puzzleId;
  final PuzzleSession session;
  final void Function(ClueCell cell) onClueCellTap;
  final void Function(int cell) onCellLongPress;

  /// Optional external control (zoom buttons).
  final TransformationController? zoomController;

  @override
  ConsumerState<PuzzleGrid> createState() => _PuzzleGridState();
}

class _PuzzleGridState extends ConsumerState<PuzzleGrid> with TickerProviderStateMixin {
  late final TransformationController _transform = widget.zoomController ?? TransformationController();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _pan = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? _panAnim;
  ClueTextLayout? _clueText;
  String? _pulseWordId;
  int? _lastSeenFeedback;
  int? _lastCell;
  Size _viewport = Size.zero;
  Offset _origin = Offset.zero;
  GridGeometry? _geometry;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _pan.addListener(() {
      final a = _panAnim;
      if (a != null) _transform.value = a.value;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _pan.dispose();
    if (widget.zoomController == null) _transform.dispose();
    _clueText?.invalidate();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PuzzleGrid old) {
    super.didUpdateWidget(old);
    final fb = widget.session.feedback;
    if (fb != null && fb.seq != _lastSeenFeedback) {
      _lastSeenFeedback = fb.seq;
      if (fb.kind == FeedbackKind.wordWrong && fb.wordId != null) _startPulse(fb.wordId!);
    }
    final cell = widget.session.selection?.cell;
    if (cell != null && cell != _lastCell) {
      _lastCell = cell;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(cell));
    }
  }

  void _startPulse(String wordId) {
    setState(() => _pulseWordId = wordId);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _pulse.value = 1;
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _pulseWordId = null);
      });
      return;
    }
    _pulse
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) setState(() => _pulseWordId = null);
      });
  }

  /// Pans (animated) so the cell is fully inside the viewport.
  void _ensureVisible(int cell) {
    final g = _geometry;
    if (g == null || _viewport == Size.zero) return;
    final rect = g.rectOfIndex(cell).shift(_origin);
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final tx = m.storage[12];
    final ty = m.storage[13];
    final left = rect.left * scale + tx;
    final top = rect.top * scale + ty;
    final right = rect.right * scale + tx;
    final bottom = rect.bottom * scale + ty;
    final pad = g.cellSize * scale * 0.5;
    var dx = 0.0;
    var dy = 0.0;
    if (left < pad) {
      dx = pad - left;
    } else if (right > _viewport.width - pad) {
      dx = _viewport.width - pad - right;
    }
    if (top < pad) {
      dy = pad - top;
    } else if (bottom > _viewport.height - pad) {
      dy = _viewport.height - pad - bottom;
    }
    if (dx == 0 && dy == 0) return;
    final target = m.clone()..translateByDouble(dx / scale, dy / scale, 0, 1);
    _clampTranslation(target, scale);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _transform.value = target;
      return;
    }
    _panAnim = Matrix4Tween(begin: m, end: target).animate(CurvedAnimation(parent: _pan, curve: Curves.easeOut));
    _pan
      ..reset()
      ..forward();
  }

  void _clampTranslation(Matrix4 m, double scale) {
    final g = _geometry;
    if (g == null) return;
    final contentW = math.max(g.width, _viewport.width) * scale;
    final contentH = math.max(g.height, _viewport.height) * scale;
    final minX = math.min(0.0, _viewport.width - contentW);
    final minY = math.min(0.0, _viewport.height - contentH);
    m.storage[12] = m.storage[12].clamp(minX, 0.0);
    m.storage[13] = m.storage[13].clamp(minY, 0.0);
  }

  void _handleTap(Offset local) {
    final g = _geometry;
    if (g == null) return;
    final pos = g.hitTest(local - _origin);
    if (pos == null) return;
    final puzzle = widget.session.puzzle;
    final index = puzzle.shape.indexOf(pos);
    if (puzzle.shape.kinds[index] == CellKind.clue) {
      for (final cc in puzzle.clueCells) {
        if (cc.pos == pos) {
          widget.onClueCellTap(cc);
          return;
        }
      }
      return;
    }
    ref.read(puzzleSessionProvider(widget.puzzleId).notifier).tapCell(index);
  }

  void _handleLongPress(Offset local) {
    final g = _geometry;
    if (g == null) return;
    final pos = g.hitTest(local - _origin);
    if (pos == null) return;
    final puzzle = widget.session.puzzle;
    final index = puzzle.shape.indexOf(pos);
    if (puzzle.shape.kinds[index] != CellKind.letter) return;
    widget.onCellLongPress(index);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final puzzle = session.puzzle;
    final colors = context.gridColors;
    final rtl = session.lang.direction == ReadingDirection.rtl;
    final fontFamily = AppTheme.fontFamilyFor(session.lang.code);
    _clueText ??= ClueTextLayout(fontFamily: fontFamily, fontFamilyFallback: AppTheme.fallbackFor(session.lang.code));

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final cell = GridGeometry.fitCellSize(viewport.width, puzzle.cols);
        final geometry = GridGeometry(rows: puzzle.rows, cols: puzzle.cols, cellSize: cell, rtl: rtl);
        final childSize = Size(math.max(geometry.width, viewport.width), math.max(geometry.height, viewport.height));
        final origin = Offset((childSize.width - geometry.width) / 2, (childSize.height - geometry.height) / 2);
        final sizeChanged = _viewport != viewport || _geometry?.cellSize != cell;
        _viewport = viewport;
        _origin = origin;
        _geometry = geometry;
        if (sizeChanged) _clueText!.invalidate();
        if (!_initialised || sizeChanged) {
          _initialised = true;
          final sel = session.selection;
          if (sel != null) WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(sel.cell));
        }
        final minScale = math.min(1.0, math.min(viewport.width / childSize.width, viewport.height / childSize.height));

        return Semantics(
          container: true,
          label: context.l10n.gridSemantics(puzzle.rows, puzzle.cols),
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            minScale: math.max(0.5, minScale),
            maxScale: 3,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: childSize.width,
              height: childSize.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _handleTap(d.localPosition),
                      onLongPressStart: (d) => _handleLongPress(d.localPosition),
                      child: ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => CustomPaint(
                            isComplex: true,
                            willChange: _pulseWordId != null,
                            painter: GridPainter(
                              session: session,
                              geometry: geometry,
                              colors: colors,
                              clueText: _clueText!,
                              letterFontFamily: fontFamily,
                              pulseWordId: _pulseWordId,
                              pulse: _pulseWordId == null ? 0 : (1 - _pulse.value) * 0.5 + 0.5 * math.sin(_pulse.value * math.pi * 3).abs(),
                            ),
                            size: childSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Transparent semantics nodes, one per cell, in reading order.
                  for (var r = 0; r < puzzle.rows; r++)
                    for (var c = 0; c < puzzle.cols; c++)
                      _CellSemantics(
                        puzzleId: widget.puzzleId,
                        session: session,
                        pos: Pos(r, c),
                        rect: geometry.cellRect(r, c).shift(origin),
                        onClueTap: widget.onClueCellTap,
                        onLongPress: widget.onCellLongPress,
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

class _CellSemantics extends ConsumerWidget {
  const _CellSemantics({
    required this.puzzleId,
    required this.session,
    required this.pos,
    required this.rect,
    required this.onClueTap,
    required this.onLongPress,
  });

  final String puzzleId;
  final PuzzleSession session;
  final Pos pos;
  final Rect rect;
  final void Function(ClueCell) onClueTap;
  final void Function(int) onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final puzzle = session.puzzle;
    final index = puzzle.shape.indexOf(pos);
    final isClue = puzzle.shape.kinds[index] == CellKind.clue;
    String label;
    VoidCallback? onTap;
    var selected = false;
    if (isClue) {
      ClueCell? cc;
      for (final c in puzzle.clueCells) {
        if (c.pos == pos) cc = c;
      }
      if (cc == null || cc.slots.isEmpty) return const SizedBox.shrink();
      final clues = cc.slots.map((s) => '${l10n.dirName(s.arrow.dir)}: ${s.text}').join('; ');
      label = l10n.clueCellSemantics(clues);
      final cell = cc;
      onTap = () => onClueTap(cell);
    } else {
      final e = session.progress.entry(index);
      final letter = e.symbol == null
          ? l10n.cellSemanticsEmpty
          : [
              session.lang.symbolName(e.symbol!),
              if (e.pencil) l10n.cellSemanticsPencil,
              if (e.status == CellStatus.markedWrong) l10n.cellSemanticsWrong,
              if (e.status == CellStatus.revealed) l10n.cellSemanticsRevealed,
              if (e.status == CellStatus.confirmedCorrect) l10n.cellSemanticsCorrect,
            ].join(', ');
      final sel = session.selection;
      final wordId = (sel != null && puzzle.wordById[sel.wordId]!.cells.contains(pos))
          ? sel.wordId
          : (puzzle.index.acrossOf[index] ?? puzzle.index.downOf[index]);
      final word = wordId == null ? null : puzzle.wordById[wordId];
      label = l10n.cellSemantics(
        pos.r + 1,
        pos.c + 1,
        letter,
        word == null ? '' : l10n.dirName(word.dir),
        word == null ? '' : puzzle.clueTextOf(word.id),
      );
      selected = sel?.cell == index;
      onTap = () => ref.read(puzzleSessionProvider(puzzleId).notifier).tapCell(index);
    }
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        onTap: onTap,
        onLongPress: isClue ? null : () => onLongPress(index),
        child: const SizedBox.expand(),
      ),
    );
  }
}
