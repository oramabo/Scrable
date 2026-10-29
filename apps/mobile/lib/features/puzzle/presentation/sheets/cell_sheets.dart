import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../application/puzzle_session.dart';

enum CellAction { revealLetter, pencilOn, pencilOff, clearWord }

/// Long-press sheet for a letter cell.
Future<CellAction?> showCellActionsSheet(
  BuildContext context, {
  required PuzzleSession session,
  required int cell,
  required int revealPrice,
}) {
  final l10n = context.l10n;
  final entry = session.progress.entry(cell);
  final canPencil = !entry.isEmpty && !entry.isLocked;
  return showModalBottomSheet<CellAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.cellActions, style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields_rounded),
            title: Text(l10n.hintRevealLetter),
            trailing: Text(revealPrice == 0 ? l10n.hintFree : l10n.hintCost(revealPrice)),
            enabled: entry.status != CellStatus.revealed,
            onTap: () => Navigator.of(ctx).pop(CellAction.revealLetter),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(entry.pencil ? l10n.pencilOff : l10n.pencilOn),
            enabled: canPencil,
            onTap: () => Navigator.of(ctx).pop(entry.pencil ? CellAction.pencilOff : CellAction.pencilOn),
          ),
          ListTile(
            leading: const Icon(Icons.backspace_outlined),
            title: Text(l10n.clearWord),
            onTap: () => Navigator.of(ctx).pop(CellAction.clearWord),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Tap on a clue cell: lists its 1–2 clues with arrow glyphs. Returns the
/// chosen word id.
Future<String?> showClueCellSheet(BuildContext context, {required PuzzleSession session, required ClueCell cell}) {
  final l10n = context.l10n;
  final dir = puzzleTextDirection(session.lang);
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.clueCellTitle, style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          Directionality(
            textDirection: dir,
            child: Column(
              children: [
                for (final slot in cell.slots)
                  ListTile(
                    leading: _ArrowIcon(arrow: slot.arrow, rtl: dir == TextDirection.rtl),
                    title: Text(slot.text, style: Theme.of(ctx).textTheme.titleMedium),
                    subtitle: Text(
                      '${l10n.dirName(slot.arrow.dir)} · ${session.patternOf(session.puzzle.wordById[slot.wordId]!)}',
                    ),
                    onTap: () => Navigator.of(ctx).pop(slot.wordId),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _ArrowIcon extends StatelessWidget {
  const _ArrowIcon({required this.arrow, required this.rtl});
  final Arrow arrow;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    // Straight arrows map to standard icons; bent arrows use a turn icon.
    final icon = switch (arrow) {
      Arrow.a => Icons.arrow_forward_rounded,
      Arrow.d => Icons.arrow_downward_rounded,
      Arrow.da => Icons.subdirectory_arrow_right_rounded,
      Arrow.ad => Icons.turn_right_rounded,
      Arrow.ua => Icons.turn_left_rounded,
      Arrow.bd => Icons.subdirectory_arrow_left_rounded,
    };
    return Icon(icon, color: color, size: 28);
  }
}

/// Play-mode picker (only before the first letter).
Future<PlayMode?> showModeSheet(BuildContext context, {required PlayMode current, required bool enabled}) {
  final l10n = context.l10n;
  return showModalBottomSheet<PlayMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.chooseMode, style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          RadioGroup<PlayMode>(
            groupValue: current,
            onChanged: (m) {
              if (enabled && m != null) Navigator.of(ctx).pop(m);
            },
            child: Column(
              children: [
                for (final mode in PlayMode.values)
                  RadioListTile<PlayMode>(
                    value: mode,
                    enabled: enabled,
                    title: Text(l10n.modeName(mode)),
                    subtitle: Text(l10n.modeDescription(mode)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
