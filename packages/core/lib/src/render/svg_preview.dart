import '../engine/final_letters.dart';
import '../lang/language_profile.dart';
import '../lang/languages.dart';
import '../model/geometry.dart';
import '../model/puzzle.dart';

/// Renders a puzzle (optionally with its solution) as an SVG string for
/// previews in the admin tool, docs and tests.
class SvgPreview {
  const SvgPreview({this.cell = 56.0, this.showSolution = true});

  final double cell;
  final bool showSolution;

  String render(Puzzle p) {
    final lang = Languages.byCode(p.lang);
    final rtl = lang.direction == ReadingDirection.rtl;
    final w = p.cols * cell, h = p.rows * cell;
    final mask = FinalLetterPolicy.mask(p);
    final buf = StringBuffer()
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${w + 2}" height="${h + 2}" viewBox="-1 -1 ${w + 2} ${h + 2}" font-family="Noto Sans Hebrew, Arial, sans-serif">')
      ..writeln('<rect x="0" y="0" width="$w" height="$h" fill="#fff" stroke="#222" stroke-width="2"/>');
    // x position of logical column c
    double x(int c) => rtl ? (p.cols - 1 - c) * cell : c * cell;
    for (var r = 0; r < p.rows; r++) {
      for (var c = 0; c < p.cols; c++) {
        final i = p.shape.index(r, c);
        final isClue = p.shape.kinds[i] == CellKind.clue;
        buf.writeln('<rect x="${x(c)}" y="${r * cell}" width="$cell" height="$cell" fill="${isClue ? '#e8e4d8' : '#fff'}" stroke="#555" stroke-width="1"/>');
        if (!isClue && showSolution && p.solution[i] >= 0) {
          final glyph = FinalLetterPolicy.display(lang, p.solution[i], mask[i]);
          buf.writeln('<text x="${x(c) + cell / 2}" y="${r * cell + cell * 0.68}" text-anchor="middle" font-size="${cell * 0.5}" fill="#1a3c8f">${_esc(glyph)}</text>');
        }
      }
    }
    for (final cc in p.clueCells) {
      final cx = x(cc.pos.c), cy = cc.pos.r * cell;
      if (cc.slots.length == 2) {
        buf.writeln('<line x1="$cx" y1="${cy + cell / 2}" x2="${cx + cell}" y2="${cy + cell / 2}" stroke="#555" stroke-width="1"/>');
      }
      for (final s in cc.slots) {
        final top = s.pos == SlotPos.bottom ? cy + cell / 2 : cy;
        final height = s.pos == SlotPos.full ? cell : cell / 2;
        final fontSize = s.pos == SlotPos.full ? cell * 0.17 : cell * 0.15;
        final lineH = fontSize * 1.15;
        final startY = top + (height - s.lines.length * lineH) / 2 + fontSize;
        for (var k = 0; k < s.lines.length; k++) {
          buf.writeln('<text x="${cx + cell / 2}" y="${startY + k * lineH}" text-anchor="middle" font-size="$fontSize" direction="${rtl ? 'rtl' : 'ltr'}" fill="#222">${_esc(s.lines[k])}</text>');
        }
        buf.writeln(_arrow(s.arrow, cx, top, height, rtl));
      }
    }
    buf.writeln('</svg>');
    return buf.toString();
  }

  /// Small arrow glyph at the edge the arrow exits from.
  String _arrow(Arrow a, double cx, double top, double height, bool rtl) {
    final size = cell * 0.16;
    final forwardX = rtl ? cx + size * 0.6 : cx + cell - size * 0.6; // forward edge
    final backX = rtl ? cx + cell - size * 0.6 : cx + size * 0.6;
    final midY = top + height / 2;
    final dir = rtl ? -1 : 1; // forward direction sign in screen space
    switch (a.exit) {
      case ArrowExit.forward:
        final bent = a == Arrow.ad; // across then down: arrow turns down
        final x0 = forwardX - dir * size * 0.8, x1 = forwardX + dir * size * 0.3;
        if (!bent) return '<path d="M$x0 $midY L$x1 $midY" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
        return '<path d="M$x0 ${midY - size * 0.4} L$x1 ${midY - size * 0.4} L$x1 ${midY + size * 0.6}" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
      case ArrowExit.bottom:
        final bent = a == Arrow.da;
        final x0 = cx + cell / 2, y0 = top + height - size * 1.1, y1 = top + height + size * 0.1;
        if (!bent) return '<path d="M$x0 $y0 L$x0 $y1" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
        return '<path d="M$x0 $y0 L$x0 $y1 L${x0 + dir * size * 0.9} $y1" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
      case ArrowExit.top:
        final x0 = cx + cell / 2, y0 = top + size * 1.1, y1 = top - size * 0.1;
        return '<path d="M$x0 $y0 L$x0 $y1 L${x0 + dir * size * 0.9} $y1" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
      case ArrowExit.back:
        final x0 = backX + dir * size * 0.8, x1 = backX - dir * size * 0.3;
        return '<path d="M$x0 $midY L$x1 $midY L$x1 ${midY + size * 0.9}" stroke="#222" stroke-width="1.5" fill="none" marker-end="url(#m)"/>${_marker()}';
    }
  }

  String _marker() => '<defs><marker id="m" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto"><path d="M0 0 L6 3 L0 6 z" fill="#222"/></marker></defs>';

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
