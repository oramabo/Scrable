import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../puzzle/application/puzzle_session.dart';

/// Three coach marks over the tutorial puzzle: tap a cell → type a letter →
/// use the clue bar. Steps 1 and 2 advance automatically from the session;
/// the last step is dismissed with a button. Never blocks input.
class TutorialCoach extends StatefulWidget {
  const TutorialCoach({super.key, required this.session, required this.onDone});

  final PuzzleSession session;
  final VoidCallback onDone;

  @override
  State<TutorialCoach> createState() => _TutorialCoachState();
}

class _TutorialCoachState extends State<TutorialCoach> {
  int _step = 0;
  int? _initialCell;

  @override
  void initState() {
    super.initState();
    _initialCell = widget.session.selection?.cell;
  }

  @override
  void didUpdateWidget(covariant TutorialCoach old) {
    super.didUpdateWidget(old);
    final s = widget.session;
    if (_step == 0 && s.selection?.cell != _initialCell) setState(() => _step = 1);
    if (_step <= 1 && s.progress.filledCount > 0) setState(() => _step = 2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final text = switch (_step) {
      0 => l10n.tutorialTapCell,
      1 => l10n.tutorialType,
      2 => l10n.tutorialClueBar,
      _ => l10n.tutorialDone,
    };
    final icon = switch (_step) {
      0 => Icons.touch_app_outlined,
      1 => Icons.keyboard_alt_outlined,
      2 => Icons.swap_horiz_rounded,
      _ => Icons.celebration_outlined,
    };
    // Steps 0/1 sit at the top (over the grid); step 2 points at the clue bar
    // so it sits just above the keyboard area.
    final alignTop = _step < 2;
    return Align(
      alignment: alignTop ? Alignment.topCenter : Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          liveRegion: true,
          child: Material(
            elevation: 6,
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: theme.colorScheme.onPrimary),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onPrimary),
                    onPressed: () {
                      if (_step >= 2) {
                        widget.onDone();
                      } else {
                        setState(() => _step++);
                      }
                    },
                    child: Text(_step >= 2 ? l10n.gotIt : l10n.next),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
