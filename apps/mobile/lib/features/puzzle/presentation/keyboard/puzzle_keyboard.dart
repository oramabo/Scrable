import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';

/// Custom in-app keyboard built from [LanguageProfile.keyboardLayouts].
///
/// Letter keys show and emit the regular letter; the layouts' final-form keys
/// are left out because grids never show final forms. Keys are ≥ 48 dp tall, show a press
/// preview and carry the letter name as their semantics label. The action
/// row has hint, geresh (Hebrew), undo, next word and backspace.
class PuzzleKeyboard extends StatefulWidget {
  const PuzzleKeyboard({
    super.key,
    required this.lang,
    required this.layout,
    required this.onSymbol,
    required this.onBackspace,
    required this.onNextWord,
    required this.onHint,
    required this.onUndo,
    this.onGeresh,
    this.big = false,
    this.enabled = true,
  });

  final LanguageProfile lang;
  final KeyboardLayout layout;
  final ValueChanged<int> onSymbol;
  final VoidCallback onBackspace;
  final VoidCallback onNextWord;
  final VoidCallback onHint;
  final VoidCallback onUndo;

  /// Null hides the geresh key (non-Hebrew layouts).
  final VoidCallback? onGeresh;
  final bool big;
  final bool enabled;

  @override
  State<PuzzleKeyboard> createState() => _PuzzleKeyboardState();
}

class _PuzzleKeyboardState extends State<PuzzleKeyboard> {
  _Preview? _preview;

  double get _keyHeight => widget.big ? 58 : 50;
  static const _gap = 5.0;

  void _showPreview(String label, Rect rect) => setState(() => _preview = _Preview(label, rect));
  void _hidePreview() {
    if (_preview != null) setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.gridColors;
    // Grids use regular letters only, so the final-form keys (ך ם ן ף ץ) are left out.
    final rows = [for (final row in widget.layout.rows) row.where((k) => !k.finalForm).toList()];
    final maxLen = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final fontFamily = AppTheme.fontFamilyFor(widget.lang.code);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final keyWidth = (width - _gap * (maxLen + 1)) / maxLen;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final k in row)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                              child: _KeyButton(
                                width: keyWidth,
                                height: _keyHeight,
                                label: widget.lang.symbolToDisplay(k.symbol),
                                semanticsLabel: l10n.keySemantics(widget.lang.symbolName(k.symbol)),
                                fontFamily: fontFamily,
                                fill: colors.keyFill,
                                textColor: colors.keyText,
                                pressed: colors.keyPressed,
                                enabled: widget.enabled,
                                onPreview: _showPreview,
                                onRelease: _hidePreview,
                                onTap: () => widget.onSymbol(k.symbol),
                              ),
                            ),
                        ],
                      ),
                    ),
                  PuzzleActionRow(
                    height: _keyHeight,
                    enabled: widget.enabled,
                    onHint: widget.onHint,
                    onGeresh: widget.onGeresh,
                    onUndo: widget.onUndo,
                    onNextWord: widget.onNextWord,
                    onBackspace: widget.onBackspace,
                  ),
                ],
              ),
            ),
            if (_preview != null)
              Positioned(
                left: _preview!.rect.center.dx - keyWidth * 0.75,
                top: _preview!.rect.top - _keyHeight * 1.15,
                width: keyWidth * 1.5,
                height: _keyHeight * 1.1,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Material(
                      elevation: 4,
                      color: colors.keyPressed,
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: Text(
                          _preview!.label,
                          style: TextStyle(
                            fontSize: _keyHeight * 0.6,
                            fontFamily: fontFamily,
                            fontWeight: FontWeight.w600,
                            color: colors.keyText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Preview {
  const _Preview(this.label, this.rect);
  final String label;
  final Rect rect;
}

class _KeyButton extends StatefulWidget {
  const _KeyButton({
    required this.width,
    required this.height,
    required this.label,
    required this.semanticsLabel,
    required this.fontFamily,
    required this.fill,
    required this.textColor,
    required this.pressed,
    required this.enabled,
    required this.onPreview,
    required this.onRelease,
    required this.onTap,
  });

  final double width;
  final double height;
  final String label;
  final String semanticsLabel;
  final String fontFamily;
  final Color fill;
  final Color textColor;
  final Color pressed;
  final bool enabled;
  final void Function(String label, Rect rect) onPreview;
  final VoidCallback onRelease;
  final VoidCallback onTap;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _down = false;

  Rect _rectInKeyboard() {
    final box = context.findRenderObject() as RenderBox?;
    final keyboard = context.findAncestorStateOfType<_PuzzleKeyboardState>()?.context.findRenderObject() as RenderBox?;
    if (box == null || keyboard == null) return Rect.zero;
    final topLeft = keyboard.globalToLocal(box.localToGlobal(Offset.zero));
    return topLeft & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.height * (widget.label.length > 1 ? 0.4 : 0.5);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      onTap: widget.enabled ? widget.onTap : null,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: widget.enabled
              ? (_) {
                  setState(() => _down = true);
                  widget.onPreview(widget.label, _rectInKeyboard());
                }
              : null,
          onPointerUp: widget.enabled
              ? (e) {
                  setState(() => _down = false);
                  widget.onRelease();
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(e.position);
                  final slop = (Offset.zero & box.size).inflate(16);
                  if (slop.contains(local)) widget.onTap();
                }
              : null,
          onPointerCancel: (_) {
            setState(() => _down = false);
            widget.onRelease();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _down ? widget.pressed : widget.fill,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), offset: const Offset(0, 1), blurRadius: 1),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: widget.fontFamily,
                fontWeight: FontWeight.w600,
                color: widget.enabled ? widget.textColor : widget.textColor.withValues(alpha: 0.4),
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hint, geresh (Hebrew), undo, next word and backspace. Under the letters of
/// [PuzzleKeyboard]; above the system keyboard, which brings its own
/// backspace. A null [onGeresh] / [onBackspace] hides that key.
class PuzzleActionRow extends StatelessWidget {
  const PuzzleActionRow({
    super.key,
    required this.onHint,
    required this.onUndo,
    required this.onNextWord,
    this.onGeresh,
    this.onBackspace,
    this.height = 50,
    this.enabled = true,
  });

  final VoidCallback onHint;
  final VoidCallback onUndo;
  final VoidCallback onNextWord;
  final VoidCallback? onGeresh;
  final VoidCallback? onBackspace;
  final double height;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.gridColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionKey(
          icon: Icons.lightbulb_outline_rounded,
          label: l10n.keyHint,
          height: height,
          flex: 3,
          fill: colors.keyActionFill,
          textColor: colors.keyText,
          onTap: onHint,
        ),
        if (onGeresh != null)
          _ActionKey(
            text: HebrewProfile.geresh,
            label: l10n.keyGeresh,
            height: height,
            flex: 2,
            fill: colors.keyFill,
            textColor: colors.keyText,
            onTap: enabled ? onGeresh : null,
          ),
        _ActionKey(
          icon: Icons.undo_rounded,
          label: l10n.keyUndo,
          height: height,
          flex: 2,
          fill: colors.keyActionFill,
          textColor: colors.keyText,
          onTap: enabled ? onUndo : null,
        ),
        _ActionKey(
          icon: Icons.skip_next_rounded,
          label: l10n.keyNextWord,
          height: height,
          flex: 3,
          fill: colors.keyActionFill,
          textColor: colors.keyText,
          onTap: onNextWord,
        ),
        if (onBackspace != null)
          _ActionKey(
            icon: Icons.backspace_outlined,
            label: l10n.keyBackspace,
            height: height,
            flex: 3,
            fill: colors.keyActionFill,
            textColor: colors.keyText,
            onTap: enabled ? onBackspace : null,
          ),
      ],
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({
    required this.label,
    required this.height,
    required this.flex,
    required this.fill,
    required this.textColor,
    required this.onTap,
    this.icon,
    this.text,
  });

  final String label;
  final double height;
  final int flex;
  final Color fill;
  final Color textColor;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? textColor.withValues(alpha: 0.4) : textColor;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: Semantics(
          button: true,
          label: label,
          enabled: onTap != null,
          child: ExcludeSemantics(
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: SizedBox(
                  height: height,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, color: color, size: height * 0.5)
                        : Text(text!, style: TextStyle(fontSize: height * 0.55, color: color, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
