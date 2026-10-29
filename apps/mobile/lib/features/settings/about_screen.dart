import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final version = ref.watch(appConfigProvider).appVersion;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              l10n.appTitle,
              style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
            ),
          ),
          Center(child: Text(l10n.aboutVersion(version), style: theme.textTheme.bodyMedium)),
          const SizedBox(height: 16),
          Text(l10n.aboutDescription, style: theme.textTheme.bodyLarge),
          SectionHeader(l10n.aboutCredits),
          ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text(l10n.aboutMordo)),
          ListTile(leading: const Icon(Icons.text_fields_rounded), title: Text(l10n.aboutFonts)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: version,
            ),
            icon: const Icon(Icons.description_outlined),
            label: Text(l10n.aboutLicenses),
          ),
        ],
      ),
    );
  }
}
