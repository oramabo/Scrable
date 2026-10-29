import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../application/puzzle_session.dart';

/// The active clue in large type with direction icon, pattern, previous/next
/// buttons and the crossing clue (tap to switch). Lives inside the puzzle's
/// Directionality.
class ClueBar extends StatelessWidget {
  const ClueBar({
    super.key,
    required this.session,
    required this.onPrev,
    required this.onNext,
    required this.onSwitch,
  });

  final PuzzleSession session;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSwitch;

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
                            const SizedBox(height: 2),
                            Semantics(
                              label: l10n.patternLabel(session.patternOf(word).replaceAll('_', l10n.cellSemanticsEmpty)),
                              child: ExcludeSemantics(
                                child: Text(
                                  session.patternOf(word),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    letterSpacing: 2,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
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
