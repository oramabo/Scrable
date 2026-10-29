import 'dart:ui';

import 'package:chetz_core/chetz_core.dart';

/// Maps logical grid coordinates to scene coordinates.
///
/// Logical column 0 is the first column in reading direction, so for RTL it
/// is drawn at the rightmost screen position: `x = (cols - 1 - c) * cell`.
class GridGeometry {
  const GridGeometry({required this.rows, required this.cols, required this.cellSize, required this.rtl});

  final int rows;
  final int cols;
  final double cellSize;
  final bool rtl;

  double get width => cols * cellSize;
  double get height => rows * cellSize;
  Size get size => Size(width, height);

  int screenCol(int c) => rtl ? cols - 1 - c : c;
  int logicalCol(int screenCol) => rtl ? cols - 1 - screenCol : screenCol;

  Rect cellRect(int r, int c) => Rect.fromLTWH(screenCol(c) * cellSize, r * cellSize, cellSize, cellSize);
  Rect rectOf(Pos p) => cellRect(p.r, p.c);
  Rect rectOfIndex(int index) => cellRect(index ~/ cols, index % cols);

  /// Logical position under a scene offset, or null when outside.
  Pos? hitTest(Offset scene) {
    if (scene.dx < 0 || scene.dy < 0 || scene.dx >= width || scene.dy >= height) return null;
    final sc = (scene.dx / cellSize).floor().clamp(0, cols - 1);
    final r = (scene.dy / cellSize).floor().clamp(0, rows - 1);
    return Pos(r, logicalCol(sc));
  }

  /// Scene x direction of the reading direction (+1 LTR, −1 RTL).
  double get forwardSign => rtl ? -1 : 1;

  /// Minimum comfortable cell size (dp).
  static const double minCell = 44;

  /// Cell size so that the grid fills [viewportWidth] but never shrinks below
  /// [minCell].
  static double fitCellSize(double viewportWidth, int cols, {double min = minCell}) {
    final fit = viewportWidth / cols;
    return fit < min ? min : fit;
  }
}
