import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_controller.dart';
import 'feedback_service.dart';

/// Opens the feedback form. [details] is attached as-is (puzzle, word and
/// clue ids from the puzzle screen); [quote] is shown above the form, e.g.
/// the clue being reported.
Future<void> showFeedbackSheet(
  BuildContext context, {
  ReportKind initialKind = ReportKind.bug,
  Map<String, Object?> details = const {},
  String? quote,
}) async {
  final result = await showModalBottomSheet<FeedbackResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FeedbackSheet(initialKind: initialKind, details: details, quote: quote),
  );
  if (result == null || !context.mounted) return;
  final l10n = context.l10n;
  showSnack(context, result == FeedbackResult.sent ? l10n.feedbackThanks : l10n.feedbackQueued, icon: Icons.mark_email_read_outlined);
}

class FeedbackSheet extends ConsumerStatefulWidget {
  const FeedbackSheet({super.key, this.initialKind = ReportKind.bug, this.details = const {}, this.quote});

  final ReportKind initialKind;
  final Map<String, Object?> details;
  final String? quote;

  @override
  ConsumerState<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<FeedbackSheet> {
  late ReportKind _kind = widget.initialKind;
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _message.text.trim().length >= 3;

  Future<void> _send() async {
    setState(() => _sending = true);
    final settings = ref.read(settingsProvider);
    final report = FeedbackReport(
      kind: _kind,
      message: _message.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      createdAt: ref.read(clockProvider).nowMs,
      context: {
        'appVersion': ref.read(appConfigProvider).appVersion,
        'platform': defaultTargetPlatform.name,
        'uiLang': settings.uiLang,
        'puzzleLang': settings.puzzleLang,
        ...widget.details,
      },
    );
    final result = await ref.read(feedbackControllerProvider).submit(report);
    ref.read(analyticsProvider).track(AnalyticsEvents.feedbackSent, {'kind': _kind.code, 'queued': result == FeedbackResult.queued});
    if (mounted) Navigator.of(context).pop(result);
  }

  String _kindLabel(ReportKind k) {
    final l10n = context.l10n;
    return switch (k) {
      ReportKind.bug => l10n.feedbackKindBug,
      ReportKind.clue => l10n.feedbackKindClue,
      ReportKind.idea => l10n.feedbackKindIdea,
      ReportKind.other => l10n.feedbackKindOther,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.feedbackTitle, style: theme.textTheme.titleLarge),
            if (widget.quote != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Text(widget.quote!, style: theme.textTheme.bodyLarge),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final k in ReportKind.values)
                  ChoiceChip(label: Text(_kindLabel(k)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: FeedbackReport.maxMessageLength,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _kind == ReportKind.clue ? l10n.feedbackClueHint : l10n.feedbackMessageHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.feedbackEmailLabel, border: const OutlineInputBorder()),
            ),
            if (widget.details.containsKey('puzzleId')) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_file_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l10n.feedbackIncludesPuzzle, style: theme.textTheme.bodySmall)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _canSend ? _send : null,
              icon: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(l10n.feedbackSend),
            ),
          ],
        ),
      ),
    );
  }
}
