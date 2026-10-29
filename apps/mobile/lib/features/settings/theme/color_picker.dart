import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import 'custom_theme.dart';

/// Simple dependency-free colour picker: a preset palette plus hue /
/// saturation / value sliders and an editable hex field.
class ColorPickerField extends StatefulWidget {
  const ColorPickerField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final Color value;
  final ValueChanged<Color> onChanged;

  static const palette = [
    Color(0xFFB5471F), Color(0xFFE0652A), Color(0xFFE0A526), Color(0xFF3E8E41),
    Color(0xFF2F6F6D), Color(0xFF1E88E5), Color(0xFF5B6FB8), Color(0xFF7B3FA0),
    Color(0xFFD81B60), Color(0xFF795548), Color(0xFFF6F1E7), Color(0xFFFFFFFF),
    Color(0xFFFFF8E1), Color(0xFFE3F2FD), Color(0xFF16140F), Color(0xFF000000),
  ];

  @override
  State<ColorPickerField> createState() => _ColorPickerFieldState();
}

class _ColorPickerFieldState extends State<ColorPickerField> {
  late HSVColor _hsv = HSVColor.fromColor(widget.value);
  late final TextEditingController _hex = TextEditingController(text: hexOf(widget.value));
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ColorPickerField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.value != _hsv.toColor()) {
      _hsv = HSVColor.fromColor(widget.value);
      _hex.text = hexOf(widget.value);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _update(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final color = hsv.toColor().withValues(alpha: 1);
    _hex.text = hexOf(color);
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final color = _hsv.toColor();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Semantics(
                    label: '${widget.label}: ${hexOf(color)}',
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.label, style: theme.textTheme.titleMedium)),
                  Text(hexOf(color), style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ColorPickerField.palette)
                    Semantics(
                      button: true,
                      label: hexOf(c),
                      selected: c == color,
                      child: ExcludeSemantics(
                        child: InkWell(
                          onTap: () => _update(HSVColor.fromColor(c)),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: c == color ? theme.colorScheme.onSurface : theme.colorScheme.outline, width: c == color ? 3 : 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _slider(l10n.hue, _hsv.hue, 360, (v) => _update(_hsv.withHue(v))),
              _slider(l10n.saturation, _hsv.saturation, 1, (v) => _update(_hsv.withSaturation(v))),
              _slider(l10n.brightnessLabel, _hsv.value, 1, (v) => _update(_hsv.withValue(v))),
              TextField(
                controller: _hex,
                decoration: InputDecoration(labelText: l10n.hexLabel, prefixText: '', isDense: true),
                textDirection: TextDirection.ltr,
                onSubmitted: (text) {
                  final parsed = parseHex(text);
                  if (parsed != null) _update(HSVColor.fromColor(parsed));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            label: label,
            semanticFormatterCallback: (v) => '$label ${(v / max * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
