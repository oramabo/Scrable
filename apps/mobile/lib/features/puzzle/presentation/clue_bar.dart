import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../application/puzzle_session.dart';
import 'picture_clue.dart';

/// The active clue in large type with direction icon, a live preview of the
/// word, previous/next buttons and the crossing clue (tap to switch). Lives
/// inside the puzzle's Directionality.
class ClueBar extends StatelessWidget {
  const ClueBar({
    super.key,
    required this.session,
    required this.onPrev,
    required this.onNext,
    required this.onSwitch,
    required this.onCellTap,
  });

  final PuzzleSession session;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSwitch;

  /// A box of the word preview was tapped: move the cursor to that cell.
  final ValueChanged<int> onCellTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final word = session.activeWord;
    final sel = session.selection;
    final puzzle = session.puzzle;
    String? crossingId;
    if (sel != null) {
      final a = puzzle.index.acrossOf[sel.cell];
      final d = puzzle.index.downOf[sel.cell];
      if (a != null && d != null) crossingId = sel.wordId == a ? d : a;
    }
    final crossing = crossingId == null ? null : puzzle.wordById[crossingId];
    final textScale = MediaQuery.textScalerOf(context);
    final clueStyle = theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.2);
    final slot = word == null ? null : puzzle.slotForWord(word.id);
    final picture = slot?.image;

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              tooltip: l10n.prevWord,
              onPressed: onPrev,
              iconSize: 28,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
            Expanded(
              child: word == null
                  ? const SizedBox(height: 56)
                  : InkWell(
                      onTap: crossing == null ? null : onSwitch,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: '${l10n.dirName(word.dir)}: ${puzzle.clueTextOf(word.id)}',
                              liveRegion: true,
                              child: ExcludeSemantics(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Icon(
                                        word.dir == Dir.across ? Icons.arrow_forward_rounded : Icons.arrow_downward_rounded,
                                        size: 22,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (picture != null) ...[
                                      PictureClueImage(lang: session.lang.code, image: picture, height: 72),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Text(
                                        puzzle.clueTextOf(word.id),
                                        style: clueStyle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Semantics(
                              label: l10n.patternLabel(session.patternOf(word).replaceAll('_', l10n.cellSemanticsEmpty)),
                              child: ExcludeSemantics(
                                child: WordPreview(session: session, word: word, onCellTap: onCellTap),
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (crossing != null)
                              Semantics(
                                button: true,
                                label: '${l10n.switchWord}: ${l10n.dirName(crossing.dir)}, ${puzzle.clueTextOf(crossing.id)}',
                                child: ExcludeSemantics(
                                  child: Row(
                                    children: [
                                      Icon(
                                        crossing.dir == Dir.across
                                            ? Icons.arrow_forward_rounded
                                            : Icons.arrow_downward_rounded,
                                        size: 16,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          puzzle.clueTextOf(crossing.id),
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                            fontSize: textScale.scale(13),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(Icons.swap_vert_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            IconButton(
              tooltip: l10n.nextWord,
              onPressed: onNext,
              iconSize: 28,
              icon: const Icon(Icons.arrow_forward_ios_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected word as a row of letter boxes that follows typing; the
/// cursor box is highlighted and tapping a box moves the cursor there. On big
/// grids this keeps the word readable while the grid itself is zoomed out.
class WordPreview extends StatelessWidget {
  const WordPreview({super.key, required this.session, required this.word, required this.onCellTap});

  final PuzzleSession session;
  final PuzzleWord word;
  final ValueChanged<int> onCellTap;

  static const double _maxBox = 40;
  static const double _minBox = 28;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.gridColors;
    final cells = [for (final p in word.cells) session.puzzle.shape.indexOf(p)];
    final cursor = session.selection?.cell;
    final fontFamily = AppTheme.fontFamilyFor(session.lang.code);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth - _gap * (cells.length - 1)) / cells.length;
        final box = fit.clamp(_minBox, _maxBox);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (k, cell) in cells.indexed) ...[
                if (k > 0) const SizedBox(width: _gap),
                _PreviewBox(
                  key: ValueKey(cell),
                  size: box,
                  letter: session.displayAt(cell),
                  entry: session.progress.entry(cell),
                  isCursor: cell == cursor,
                  fontFamily: fontFamily,
                  colors: colors,
                  onTap: () => onCellTap(cell),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({
    super.key,
    required this.size,
    required this.letter,
    required this.entry,
    required this.isCursor,
    required this.fontFamily,
    required this.colors,
    required this.onTap,
  });

  final double size;
  final String letter;
  final CellEntry entry;
  final bool isCursor;
  final String fontFamily;
  final GridColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = switch (entry.status) {
      CellStatus.markedWrong => colors.wrongTint,
      CellStatus.revealed => colors.revealedTint,
      CellStatus.confirmedCorrect => colors.correctTint,
      _ => null,
    };
    final base = isCursor ? colors.activeCell : colors.activeWord;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint == null ? base : Color.alphaBlend(tint, base),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isCursor ? colors.activeBorder : colors.gridLine, width: isCursor ? 2.5 : 1),
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
          child: Text(
            letter,
            key: ValueKey(letter),
            style: TextStyle(
              fontSize: size * 0.58,
              height: 1,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w700,
              color: entry.pencil ? colors.pencilText : colors.letterText,
            ),
          ),
        ),
      ),
    );
  }
}
