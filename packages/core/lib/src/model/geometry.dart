/// Grid geometry shared by the model, engine and generator.
///
/// Columns are counted from the first column in the language's reading
/// direction: `c + 1` is the next cell *along* the reading direction.
library;

enum Dir { across, down }

enum CellKind { letter, clue }

/// Where the first letter of a word sits relative to its clue cell and which
/// way the word runs.
///
/// * [a]  across: first letter is the next cell along the reading direction.
/// * [d]  down: first letter is the cell below.
/// * [da] down-then-across: first letter below, word runs across.
/// * [ad] across-then-down: first letter is the next cell across, word runs down.
/// * [ua] up-then-across: first letter above, word runs across (rare).
/// * [bd] back-then-down: first letter is the previous cell, word runs down (rare).
enum Arrow {
  a('A', Dir.across, 0, 1, ArrowExit.forward, 0),
  d('D', Dir.down, 1, 0, ArrowExit.bottom, 0),
  da('DA', Dir.across, 1, 0, ArrowExit.bottom, 1),
  ad('AD', Dir.down, 0, 1, ArrowExit.forward, 1),
  ua('UA', Dir.across, -1, 0, ArrowExit.top, 2),
  bd('BD', Dir.down, 0, -1, ArrowExit.back, 2);

  const Arrow(this.code, this.dir, this.startDr, this.startDc, this.exit, this.cost);

  /// JSON code.
  final String code;

  /// Direction the word runs.
  final Dir dir;

  /// Offset from the clue cell to the first letter.
  final int startDr;
  final int startDc;

  /// Edge of the clue cell through which the arrow leaves.
  final ArrowExit exit;

  /// Layout cost: straight arrows are free, bent arrows cost 1, rare ones 2.
  final int cost;

  bool get isBent => this != a && this != d;

  static Arrow fromCode(String code) =>
      Arrow.values.firstWhere((v) => v.code == code, orElse: () => throw FormatException('unknown arrow $code'));

  /// Arrows that can clue a word running in [dir].
  static List<Arrow> forDir(Dir dir) => Arrow.values.where((v) => v.dir == dir).toList();
}

/// Edge of a clue cell an arrow exits through. `forward` points along the
/// reading direction (left in Hebrew, right in English).
enum ArrowExit { forward, back, top, bottom }

/// Half of a split clue cell (or the whole cell).
enum SlotPos {
  top('top'),
  bottom('bottom'),
  full('full');

  const SlotPos(this.code);
  final String code;

  static SlotPos fromCode(String code) =>
      SlotPos.values.firstWhere((v) => v.code == code, orElse: () => throw FormatException('unknown slot $code'));

  /// Which exits a slot may use: the top half cannot exit through the bottom
  /// edge and vice versa.
  bool allows(ArrowExit exit) {
    switch (this) {
      case SlotPos.full:
        return true;
      case SlotPos.top:
        return exit != ArrowExit.bottom;
      case SlotPos.bottom:
        return exit != ArrowExit.top;
    }
  }
}

class Pos {
  const Pos(this.r, this.c);
  final int r;
  final int c;

  Pos operator +(Pos o) => Pos(r + o.r, c + o.c);
  Pos step(Dir dir, int k) => dir == Dir.across ? Pos(r, c + k) : Pos(r + k, c);

  @override
  bool operator ==(Object other) => other is Pos && other.r == r && other.c == c;
  @override
  int get hashCode => r * 1024 + c;
  @override
  String toString() => '($r,$c)';

  Map<String, int> toJson() => {'r': r, 'c': c};
  static Pos fromJson(Map<String, dynamic> j) => Pos(j['r'] as int, j['c'] as int);
}

/// Rectangular grid of cell kinds with index helpers.
class GridShape {
  GridShape(this.rows, this.cols, List<CellKind> kinds)
      : kinds = List.unmodifiable(kinds) {
    if (kinds.length != rows * cols) {
      throw ArgumentError('kinds has ${kinds.length} cells, expected ${rows * cols}');
    }
  }

  /// Parses row strings such as `"CLLLC"` (`C` clue, `L` letter).
  factory GridShape.fromRows(List<String> rowStrings) {
    final rows = rowStrings.length;
    final cols = rowStrings.first.length;
    final kinds = <CellKind>[];
    for (final row in rowStrings) {
      if (row.length != cols) throw ArgumentError('ragged layout rows');
      for (final ch in row.split('')) {
        kinds.add(ch == 'C' ? CellKind.clue : CellKind.letter);
      }
    }
    return GridShape(rows, cols, kinds);
  }

  final int rows;
  final int cols;
  final List<CellKind> kinds;

  int get cellCount => rows * cols;
  int index(int r, int c) => r * cols + c;
  int indexOf(Pos p) => index(p.r, p.c);
  Pos pos(int index) => Pos(index ~/ cols, index % cols);
  bool inBounds(int r, int c) => r >= 0 && c >= 0 && r < rows && c < cols;
  bool inBoundsPos(Pos p) => inBounds(p.r, p.c);
  CellKind kindAt(int r, int c) => kinds[index(r, c)];
  bool isLetter(int r, int c) => inBounds(r, c) && kindAt(r, c) == CellKind.letter;
  bool isClue(int r, int c) => inBounds(r, c) && kindAt(r, c) == CellKind.clue;

  int get letterCount => kinds.where((k) => k == CellKind.letter).length;

  List<String> toRows() => [
        for (var r = 0; r < rows; r++)
          [for (var c = 0; c < cols; c++) kindAt(r, c) == CellKind.clue ? 'C' : 'L'].join(),
      ];
}
