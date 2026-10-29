import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/common.dart';
import 'random_puzzle_providers.dart';

/// Generates a random puzzle of [level] behind a small "preparing…" dialog and
/// returns its id (null on failure, after a toast).
Future<String?> startRandomPuzzle(BuildContext context, WidgetRef ref, int level, {String? lang}) async {
  final l10n = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogOpen = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.randomPreparing)),
          ],
        ),
      ),
    ),
  ).whenComplete(() => dialogOpen = false));
  String? id;
  Object? error;
  try {
    id = await createRandomPuzzleFrom(ref, level, lang: lang);
  } catch (e) {
    error = e;
    logRandomFailure(e);
  }
  if (dialogOpen && navigator.mounted) navigator.pop();
  if (!context.mounted) return null;
  if (id == null) {
    showSnack(context, l10n.randomFailed, icon: Icons.error_outline_rounded);
    assert(error != null);
  }
  return id;
}
