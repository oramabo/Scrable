import 'dart:math' as math;

import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/puzzle_session.dart';
import 'grid_geometry.dart';

/// Caches laid-out clue text per (cell, slot, cell size) so the painter never
/// re-shapes text on every frame.
class ClueTextLayout {
  ClueTextLayout({required this.fontFamily, this.fontFamilyFallback = const []});

  final String fontFamily;
  final List<String> fontFamilyFallback;
  final Map<String, TextPainter> _cache = {};
  Color? _color;

  void invalidate() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }

  /// Fits the pre-broken [lines] into [area]; the font shrinks until both the
  /// width and height fit (never below 11% of the cell).
  TextPainter painterFor({
    required String key,
    required List<String> lines,
    required Size area,
    required double cellSize,
    required Color color,
    required TextDirection direction,
  }) {
    if (_color != color) {
      invalidate();
      _color = color;
    }
    final cacheKey = '$key/${cellSize.toStringAsFixed(1)}/${area.height.toStringAsFixed(1)}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final text = lines.join('\n');
    var fontSize = cellSize * 0.2;
    final minFont = cellSize * 0.11;
    TextPainter build(double size) => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              height: 1.08,
              color: color,
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
              fontWeight: FontWeight.w500,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: direction,
          maxLines: lines.length,
        )..layout(minWidth: 0, maxWidth: area.width * 3);

    var painter = build(fontSize);
    for (var i = 0; i < 4; i++) {
      final scale = math.min(area.width / math.max(painter.width, 1), area.height / math.max(painter.height, 1));
      if (scale >= 1) break;
      final next = math.max(minFont, fontSize * scale * 0.98);
      if ((next - fontSize).abs() < 0.1) break;
      fontSize = next;
      painter.dispose();
      painter = build(fontSize);
      if (fontSize <= minFont) break;
    }
    painter.layout(minWidth: 0, maxWidth: math.max(painter.width, area.width));
    _cache[cacheKey] = painter;
    return painter;
  }
}

/// Paints the whole grid: clue cells (shaded, clue lines, arrows, dividers),
/// letter cells (letters, pencil marks, status tints + icons), the active
/// word/cell and the "wrong word" pulse. Excluded from semantics; the
/// overlay in puzzle_grid.dart provides them.
class GridPainter extends CustomPainter {
  GridPainter({
    required this.session,
    required this.geometry,
    required this.colors,
    required this.clueText,
    required this.letterFontFamily,
    required this.pulseWordId,
    required this.pulse,
  });

  final PuzzleSession session;
  final GridGeometry geometry;
  final GridColors colors;
  final ClueTextLayout clueText;
  final String letterFontFamily;
  final String? pulseWordId;

  /// 0..1 intensity of the wrong-word outline.
  final double pulse;

  Puzzle get puzzle => session.puzzle;
  TextDirection get textDirection => geometry.rtl ? TextDirection.rtl : TextDirection.ltr;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = geometry.cellSize;
    final shape = puzzle.shape;
    final sel = session.selection;
    final activeCells = <int>{};
    if (sel != null) {
      final w = puzzle.wordById[sel.wordId];
      if (w != null) activeCells.addAll(w.cells.map(shape.indexOf));
    }

    final fill = Paint()..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, fill..color = colors.paper);

    // 1. Cell backgrounds.
    for (var i = 0; i < shape.cellCount; i++) {
      final rect = geometry.rectOfIndex(i);
      if (shape.kinds[i] == CellKind.clue) {
        canvas.drawRect(rect, fill..color = colors.clueFill);
        continue;
      }
      canvas.drawRect(rect, fill..color = colors.letterFill);
      final e = session.progress.entry(i);
      Color? tint;
      switch (e.status) {
        case CellStatus.confirmedCorrect:
          tint = colors.correctTint;
        case CellStatus.markedWrong:
          tint = colors.wrongTint;
        case CellStatus.revealed:
          tint = colors.revealedTint;
        case CellStatus.empty:
        case CellStatus.filled:
          tint = null;
      }
      if (tint != null) canvas.drawRect(rect, fill..color = tint);
      if (activeCells.contains(i)) {
        canvas.drawRect(rect, fill..color = colors.activeWord.withValues(alpha: tint == null ? 1 : 0.6));
      }
      if (sel != null && sel.cell == i) {
        canvas.drawRect(rect, fill..color = colors.activeCell.withValues(alpha: 0.85));
      }
    }

    // 2. Clue text, dividers and arrows.
    for (final cc in puzzle.clueCells) {
      final rect = geometry.rectOf(cc.pos);
      if (cc.slots.length > 1) {
        canvas.drawLine(
          Offset(rect.left + cell * 0.08, rect.center.dy),
          Offset(rect.right - cell * 0.08, rect.center.dy),
          Paint()
            ..color = colors.gridLine
            ..strokeWidth = colors.lineWidth,
        );
      }
      for (var k = 0; k < cc.slots.length; k++) {
        final slot = cc.slots[k];
        final slotRect = _slotRect(rect, slot.pos);
        _paintArrow(canvas, slotRect, slot.arrow, cell);
        final area = _textArea(slotRect, slot.arrow, cell);
        final painter = clueText.painterFor(
          key: '${cc.pos.r}:${cc.pos.c}:$k',
          lines: slot.lines,
          area: area.size,
          cellSize: cell,
          color: colors.clueText,
          direction: textDirection,
        );
        final offset = Offset(
          area.center.dx - painter.width / 2,
          area.center.dy - painter.height / 2,
        );
        painter.paint(canvas, offset);
      }
    }

    // 3. Letters and status icons.
    for (var i = 0; i < shape.cellCount; i++) {
      if (shape.kinds[i] != CellKind.letter) continue;
      final e = session.progress.entry(i);
      final rect = geometry.rectOfIndex(i);
      if (e.symbol != null) {
        final text = session.displayAt(i);
        final isPencil = e.pencil && !e.isLocked;
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: cell * (isPencil ? 0.42 : 0.58),
              color: isPencil ? colors.pencilText : colors.letterText,
              fontFamily: letterFontFamily,
              fontWeight: isPencil ? FontWeight.w400 : FontWeight.w600,
              height: 1,
            ),
          ),
          textDirection: textDirection,
        )..layout();
        // Geresh letters are two glyphs: shrink to fit.
        var scale = 1.0;
        if (tp.width > cell * 0.82) scale = cell * 0.82 / tp.width;
        canvas.save();
        canvas.translate(rect.center.dx, rect.center.dy + (isPencil ? cell * 0.08 : 0));
        canvas.scale(scale);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
        tp.dispose();
      }
      // Icons: never colour-only.
      final iconSize = cell * 0.2;
      final corner = Offset(
        geometry.rtl ? rect.left + cell * 0.08 : rect.right - cell * 0.08 - iconSize,
        rect.top + cell * 0.08,
      );
      if (e.status == CellStatus.markedWrong) {
        final p = Paint()
          ..color = colors.wrongMark
          ..strokeWidth = math.max(1.5, cell * 0.045)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(corner, corner + Offset(iconSize, iconSize), p);
        canvas.drawLine(corner + Offset(iconSize, 0), corner + Offset(0, iconSize), p);
      } else if (e.status == CellStatus.revealed) {
        canvas.drawCircle(corner + Offset(iconSize / 2, iconSize / 2), cell * 0.06, fill..color = colors.revealedMark);
      }
    }

    // 4. Grid lines.
    final line = Paint()
      ..color = colors.gridLine
      ..strokeWidth = colors.lineWidth
      ..style = PaintingStyle.stroke;
    for (var r = 0; r <= geometry.rows; r++) {
      final y = r * cell;
      canvas.drawLine(Offset(0, y), Offset(geometry.width, y), line);
    }
    for (var c = 0; c <= geometry.cols; c++) {
      final x = c * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, geometry.height), line);
    }

    // 5. Active cell border.
    if (sel != null) {
      final rect = geometry.rectOfIndex(sel.cell).deflate(1);
      canvas.drawRect(
        rect,
        Paint()
          ..color = colors.activeBorder
          ..strokeWidth = math.max(2, colors.lineWidth + 1)
          ..style = PaintingStyle.stroke,
      );
    }

    // 6. Wrong-word pulse: outline the word's bounding box.
    if (pulseWordId != null && pulse > 0) {
      final w = puzzle.wordById[pulseWordId];
      if (w != null) {
        Rect? bounds;
        for (final p in w.cells) {
          final r = geometry.rectOf(p);
          bounds = bounds == null ? r : bounds.expandToInclude(r);
        }
        if (bounds != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(bounds.deflate(1.5), const Radius.circular(3)),
            Paint()
              ..color = colors.wrongMark.withValues(alpha: pulse.clamp(0, 1))
              ..strokeWidth = 3
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
  }

  Rect _slotRect(Rect cell, SlotPos pos) => switch (pos) {
        SlotPos.full => cell,
        SlotPos.top => Rect.fromLTRB(cell.left, cell.top, cell.right, cell.center.dy),
        SlotPos.bottom => Rect.fromLTRB(cell.left, cell.center.dy, cell.right, cell.bottom),
      };

  /// Text area inside a slot: a margin on the arrow's exit side plus padding.
  Rect _textArea(Rect slot, Arrow arrow, double cell) {
    final pad = cell * 0.05;
    final reserve = cell * 0.17;
    var l = slot.left + pad, t = slot.top + pad, r = slot.right - pad, b = slot.bottom - pad;
    final forwardIsLeft = geometry.rtl;
    switch (arrow.exit) {
      case ArrowExit.forward:
        if (forwardIsLeft) {
          l += reserve;
        } else {
          r -= reserve;
        }
      case ArrowExit.back:
        if (forwardIsLeft) {
          r -= reserve;
        } else {
          l += reserve;
        }
      case ArrowExit.bottom:
        b -= reserve;
      case ArrowExit.top:
        t += reserve;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Arrow glyph near the exit edge of the slot; forward direction is mirrored
  /// for RTL. Straight arrows are a single stroke; bent ones have an elbow.
  void _paintArrow(Canvas canvas, Rect slot, Arrow arrow, double cell) {
    final paint = Paint()
      ..color = colors.arrow
      ..strokeWidth = math.max(1.4, cell * 0.04)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final len = cell * 0.2;
    final sign = geometry.forwardSign;
    final inset = cell * 0.06;
    final forwardEdge = sign > 0 ? slot.right - inset : slot.left + inset;
    final backEdge = sign > 0 ? slot.left + inset : slot.right - inset;
    final path = Path();
    Offset tip;
    Offset dir;
    switch (arrow) {
      case Arrow.a:
        tip = Offset(forwardEdge, slot.center.dy);
        path.moveTo(forwardEdge - sign * len, slot.center.dy);
        path.lineTo(tip.dx, tip.dy);
        dir = Offset(sign, 0);
      case Arrow.d:
        tip = Offset(slot.center.dx, slot.bottom - inset);
        path.moveTo(slot.center.dx, slot.bottom - inset - len);
        path.lineTo(tip.dx, tip.dy);
        dir = const Offset(0, 1);
      case Arrow.da:
        final x = slot.center.dx - sign * len * 0.4;
        final y = slot.bottom - inset;
        path.moveTo(x, y - len * 0.8);
        path.lineTo(x, y);
        tip = Offset(x + sign * len * 0.8, y);
        path.lineTo(tip.dx, tip.dy);
        dir = Offset(sign, 0);
      case Arrow.ad:
        final y = slot.center.dy - len * 0.4;
        path.moveTo(forwardEdge - sign * len * 0.8, y);
        path.lineTo(forwardEdge, y);
        tip = Offset(forwardEdge, y + len * 0.8);
        path.lineTo(tip.dx, tip.dy);
        dir = const Offset(0, 1);
      case Arrow.ua:
        final x = slot.center.dx - sign * len * 0.4;
        final y = slot.top + inset;
        path.moveTo(x, y + len * 0.8);
        path.lineTo(x, y);
        tip = Offset(x + sign * len * 0.8, y);
        path.lineTo(tip.dx, tip.dy);
        dir = Offset(sign, 0);
      case Arrow.bd:
        final y = slot.center.dy - len * 0.4;
        path.moveTo(backEdge + sign * len * 0.8, y);
        path.lineTo(backEdge, y);
        tip = Offset(backEdge, y + len * 0.8);
        path.lineTo(tip.dx, tip.dy);
        dir = const Offset(0, 1);
    }
    canvas.drawPath(path, paint);
    // Arrow head.
    final head = len * 0.45;
    final perp = Offset(-dir.dy, dir.dx);
    final headPath = Path()
      ..moveTo(tip.dx - dir.dx * head + perp.dx * head * 0.7, tip.dy - dir.dy * head + perp.dy * head * 0.7)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - dir.dx * head - perp.dx * head * 0.7, tip.dy - dir.dy * head - perp.dy * head * 0.7);
    canvas.drawPath(headPath, paint);
  }

  @override
  bool shouldRepaint(covariant GridPainter old) =>
      old.session != session ||
      old.geometry.cellSize != geometry.cellSize ||
      old.colors != colors ||
      old.pulse != pulse ||
      old.pulseWordId != pulseWordId;
}
