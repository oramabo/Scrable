import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../settings_controller.dart';
import 'color_picker.dart';
import 'custom_theme.dart';

/// Settings → Theme: preset (system / light / dark / high contrast) or a
/// custom palette with live preview and WCAG contrast warnings.
class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final custom = s.customTheme;
    final report = ContrastReport.of(custom);
    final preset = s.useCustomTheme
        ? 'custom'
        : s.highContrast
            ? 'contrast'
            : s.themeMode.name;

    void choose(String v) {
      switch (v) {
        case 'custom':
          ctl.update((x) => x.copyWith(useCustomTheme: true, highContrast: false));
        case 'contrast':
          ctl.update((x) => x.copyWith(useCustomTheme: false, highContrast: true));
        default:
          ctl.update((x) => x.copyWith(
                useCustomTheme: false,
                highContrast: false,
                themeMode: ThemeMode.values.firstWhere((m) => m.name == v),
              ));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTheme)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RadioGroup<String>(
            groupValue: preset,
            onChanged: (v) => v == null ? null : choose(v),
            child: Column(
              children: [
                RadioListTile<String>(value: 'system', title: Text(l10n.themeSystem)),
                RadioListTile<String>(value: 'light', title: Text(l10n.themeLight)),
                RadioListTile<String>(value: 'dark', title: Text(l10n.themeDark)),
                RadioListTile<String>(value: 'contrast', title: Text(l10n.themeHighContrast)),
                RadioListTile<String>(value: 'custom', title: Text(l10n.themeCustom)),
              ],
            ),
          ),
          if (s.useCustomTheme) ...[
            const SizedBox(height: 8),
            Text(l10n.customThemeTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Preview(custom: custom, uiLang: s.uiLang),
            const SizedBox(height: 8),
            if (!report.isApplicable)
              Card(
                color: theme.colorScheme.error.withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(Icons.block_rounded, color: theme.colorScheme.error),
                  title: Text(l10n.themeRefused, style: theme.textTheme.bodyMedium),
                ),
              ),
            _ContrastLine(ok: report.textOk, ratio: report.textOnBackground, what: l10n.colorBackground),
            _ContrastLine(ok: report.primaryOk, ratio: report.primaryOnBackground, what: l10n.colorPrimary),
            _ContrastLine(ok: report.highlightOk, ratio: report.textOnHighlight, what: l10n.colorHighlight),
            const SizedBox(height: 8),
            ColorPickerField(
              label: l10n.colorPrimary,
              value: custom.primary,
              onChanged: (c) => ctl.update((x) => x.copyWith(customTheme: x.customTheme.copyWith(primary: c))),
            ),
            const SizedBox(height: 8),
            ColorPickerField(
              label: l10n.colorBackground,
              value: custom.background,
              onChanged: (c) => ctl.update((x) => x.copyWith(customTheme: x.customTheme.copyWith(background: c))),
            ),
            const SizedBox(height: 8),
            ColorPickerField(
              label: l10n.colorHighlight,
              value: custom.highlight,
              onChanged: (c) => ctl.update((x) => x.copyWith(customTheme: x.customTheme.copyWith(highlight: c))),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => ctl.update((x) => x.copyWith(customTheme: const CustomTheme())),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.resetColors),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContrastLine extends StatelessWidget {
  const _ContrastLine({required this.ok, required this.ratio, required this.what});
  final bool ok;
  final double ratio;
  final String what;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final text = ratio.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
              size: 18, color: ok ? theme.colorScheme.primary : theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$what: ${ok ? l10n.contrastOk(text) : l10n.contrastWarning(text)}',
              style: theme.textTheme.bodySmall?.copyWith(color: ok ? null : theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini grid + button rendered with the candidate colours.
class _Preview extends StatelessWidget {
  const _Preview({required this.custom, required this.uiLang});
  final CustomTheme custom;
  final String uiLang;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grid = GridColors.custom(custom);
    final letters = uiLang == 'he' ? ['ח', 'ץ', '', 'א'] : ['C', 'H', '', 'Z'];
    return Theme(
      data: AppTheme.build(brightness: custom.brightness, highContrast: false, uiLang: uiLang, custom: custom),
      child: Builder(
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: grid.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: grid.gridLine)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < letters.length; i++)
                    Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: i == 2 ? grid.activeCell : (i == 3 ? grid.activeWord : grid.letterFill),
                        border: Border.all(color: i == 2 ? grid.activeBorder : grid.gridLine, width: i == 2 ? 2 : 1),
                      ),
                      alignment: Alignment.center,
                      child: Text(letters[i], style: TextStyle(color: grid.letterText, fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: () {}, child: Text(l10n.previewLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
