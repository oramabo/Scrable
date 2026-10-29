import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/game_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/providers.dart';
import '../../../../core/widgets/common.dart';
import '../../../settings/settings_controller.dart';
import '../../../wallet/wallet_controller.dart';

/// Hint menu: returns the chosen [HintType] or null.
Future<HintType?> showHintSheet(BuildContext context, {required int level, required PlayMode mode}) {
  return showModalBottomSheet<HintType>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HintSheet(level: level, mode: mode),
  );
}

class _HintSheet extends ConsumerWidget {
  const _HintSheet({required this.level, required this.mode});

  final int level;
  final PlayMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = ref.watch(gameConfigProvider);
    final balance = ref.watch(balanceProvider);
    final freeLeft = ref.watch(freeHintsLeftProvider);
    final theme = Theme.of(context);

    Widget tile(HintType type, IconData icon, String title, {String? subtitle}) {
      final price = config.hintPrice(type, level: level, mode: mode);
      final free = price == 0 || freeLeft > 0;
      return ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Chip(
          avatar: price == 0 ? null : const Icon(Icons.monetization_on_rounded, size: 18, color: Color(0xFFE0A526)),
          label: Text(price == 0 ? l10n.hintFree : (free ? '${l10n.hintFree} · $price' : '$price')),
          visualDensity: VisualDensity.compact,
        ),
        onTap: () => Navigator.of(context).pop(type),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.hintsTitle, style: theme.textTheme.titleLarge)),
                  CoinChip(balance: balance, compact: true),
                ],
              ),
            ),
            if (freeLeft > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(l10n.hintFreeLeft(freeLeft), style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 4),
            tile(HintType.revealLetter, Icons.text_fields_rounded, l10n.hintRevealLetter),
            tile(HintType.randomLetter, Icons.casino_outlined, l10n.hintRandomLetter),
            tile(HintType.smartLetter, Icons.auto_awesome_rounded, l10n.hintSmartLetter, subtitle: l10n.hintSmartLetterDescription),
            tile(HintType.revealWord, Icons.spellcheck_rounded, l10n.hintRevealWord),
            const Divider(height: 1),
            tile(HintType.checkWord, Icons.check_circle_outline_rounded, l10n.hintCheckWord),
            tile(HintType.checkPuzzle, Icons.fact_check_outlined, l10n.hintCheckPuzzle),
            tile(HintType.firstLetters, Icons.bolt_rounded, l10n.hintFirstLetters),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Confirmation with a "don't ask again" switch. Returns true to proceed.
Future<bool> confirmHint(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required int price,
  required bool free,
}) async {
  final settings = ref.read(settingsProvider);
  if (settings.skipHintConfirm || price == 0) return true;
  final l10n = context.l10n;
  var dontAsk = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.hintConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(free ? l10n.hintConfirmFree(name) : l10n.hintConfirmBody(name, price)),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: dontAsk,
              onChanged: (v) => setState(() => dontAsk = v ?? false),
              title: Text(l10n.dontAskAgain),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.useHint)),
        ],
      ),
    ),
  );
  if (result == true && dontAsk) ref.read(settingsProvider.notifier).setSkipHintConfirm(true);
  return result == true;
}

String hintName(AppLocalizations l10n, HintType type) => switch (type) {
      HintType.revealLetter => l10n.hintRevealLetter,
      HintType.randomLetter => l10n.hintRandomLetter,
      HintType.smartLetter => l10n.hintSmartLetter,
      HintType.revealWord => l10n.hintRevealWord,
      HintType.checkWord => l10n.hintCheckWord,
      HintType.checkPuzzle => l10n.hintCheckPuzzle,
      HintType.firstLetters => l10n.hintFirstLetters,
    };
