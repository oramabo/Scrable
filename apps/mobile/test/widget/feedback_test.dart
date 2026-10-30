import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/features/feedback/feedback_service.dart';
import 'package:chetz_app/features/feedback/feedback_sheet.dart';
import 'package:chetz_app/features/feedback/rating_prompt.dart';
import 'package:chetz_app/features/feedback/review_service.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/settings/settings_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;

  setUpAll(() async {
    content = await loadBundledContent();
  });

  const puzzleId = tutorialPuzzleId;

  testWidgets('"Report this clue" sends a clue report with the puzzle, word and clue ids', (tester) async {
    usePhoneSurface(tester);
    final service = FakeFeedbackService();
    await tester.pumpWidget(wrapScreen(
      const PuzzleScreen(puzzleId: puzzleId),
      overrides: testOverrides(content: content, extra: [feedbackServiceProvider.overrideWithValue(service)]),
    ));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final word = session.activeWord!;
    final clueText = session.puzzle.clueTextOf(word.id);

    await tester.tap(find.byTooltip('תפריט'));
    await settle(tester);
    await tester.tap(find.text('דיווח על ההגדרה'));
    await settle(tester);

    expect(find.byType(FeedbackSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(FeedbackSheet), matching: find.text(clueText)), findsOneWidget);
    final clueChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'הגדרה'));
    expect(clueChip.selected, isTrue);

    await tester.enterText(find.byType(TextField).first, 'ההגדרה לא מתאימה לתשובה');
    await tester.pump();
    await tester.tap(find.text('שליחה'));
    await settle(tester);

    final report = service.sent.single;
    expect(report.kind, ReportKind.clue);
    expect(report.message, 'ההגדרה לא מתאימה לתשובה');
    expect(report.context['puzzleId'], puzzleId);
    expect(report.context['wordId'], word.id);
    expect(report.context['clueId'], word.clueId);
    expect(report.context['uiLang'], 'he');
    expect(find.byType(FeedbackSheet), findsNothing);
    expect(find.text('תודה! המשוב נשלח'), findsOneWidget);
  });

  testWidgets('the store review dialog is requested once when due, then waits for the cooldown', (tester) async {
    final review = FakeReviewService();
    final now = DateTime(2026, 10, 28, 12).millisecondsSinceEpoch;
    late WidgetRef widgetRef;
    await tester.pumpWidget(wrapScreen(
      Consumer(builder: (context, ref, _) {
        widgetRef = ref;
        return const SizedBox();
      }),
      overrides: testOverrides(
        content: content,
        settings: AppSettings(onboardingDone: true, tutorialDone: true, installedAt: now - 5 * 24 * 60 * 60 * 1000),
        meta: const MetaState(stats: PlayerStats(puzzlesCompleted: RatingPolicy.minPuzzlesCompleted)),
        review: review,
      ),
    ));
    await settle(tester);

    expect(await maybeRequestReview(widgetRef), isTrue);
    expect(review.requests, 1);
    final settings = widgetRef.read(settingsProvider);
    expect(settings.reviewPromptCount, 1);
    expect(settings.reviewPromptedAt, now);

    expect(await maybeRequestReview(widgetRef), isFalse);
    expect(review.requests, 1);
  });
}
