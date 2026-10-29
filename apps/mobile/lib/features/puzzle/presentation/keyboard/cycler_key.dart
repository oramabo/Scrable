import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/alphabet_cycler.dart';

/// The A→Z / א→ת key. Tap: next letter as a preview; long-press: auto-run
/// through the alphabet (~4 letters/s) until released or tapped again. A
/// confirm button appears while a preview letter is shown.
class CyclerKey extends StatefulWidget {
  const CyclerKey({
    super.key,
    required this.label,
    required this.cycling,
    required this.previewLabel,
    required this.onNext,
    required this.onConfirm,
    required this.onCancel,
    this.height = 48,
  });

  /// "א→ת" or "A→Z".
  final String label;
  final bool cycling;

  /// The letter currently previewed (shown on the confirm button).
  final String? previewLabel;
  final VoidCallback onNext;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final double height;

  @override
  State<CyclerKey> createState() => _CyclerKeyState();
}

class _CyclerKeyState extends State<CyclerKey> {
  Timer? _auto;

  bool get running => _auto != null;

  void _startAuto() {
    _auto?.cancel();
    widget.onNext();
    _auto = Timer.periodic(AlphabetCycler.autoRunInterval, (_) => widget.onNext());
    setState(() {});
  }

  void _stopAuto() {
    _auto?.cancel();
    _auto = null;
    if (mounted) setState(() {});
  }

  void _tap() {
    if (running) {
      _stopAuto();
    } else {
      widget.onNext();
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.gridColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Semantics(
              button: true,
              label: l10n.cyclerSemantics,
              hint: l10n.cyclerHint,
              onTap: _tap,
              onLongPress: _startAuto,
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: _tap,
                  onLongPressStart: (_) => _startAuto(),
                  onLongPressEnd: (_) => _stopAuto(),
                  onLongPressCancel: _stopAuto,
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: running ? colors.keyPressed : theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(running ? Icons.pause_rounded : Icons.cached_rounded, color: running ? colors.keyText : theme.colorScheme.onPrimary),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: running ? colors.keyText : theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.cycling) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  _stopAuto();
                  widget.onConfirm();
                },
                icon: const Icon(Icons.check_rounded),
                label: Text('${l10n.cyclerConfirm} ${widget.previewLabel ?? ''}'),
                style: FilledButton.styleFrom(minimumSize: Size(0, widget.height)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.cancel,
              onPressed: () {
                _stopAuto();
                widget.onCancel();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }
}
