import 'package:chetz_app/core/l10n/l10n.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget keyboard({
  required KeyboardLayout layout,
  required List<int> emitted,
  List<String>? actions,
  LanguageProfile lang = Languages.he,
}) {
  return MaterialApp(
    locale: const Locale('he'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Directionality(
        textDirection: puzzleTextDirection(lang),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: PuzzleKeyboard(
            lang: lang,
            layout: layout,
            onSymbol: emitted.add,
            onBackspace: () => actions?.add('backspace'),
            onNextWord: () => actions?.add('next'),
            onHint: () => actions?.add('hint'),
            onUndo: () => actions?.add('undo'),
            onGeresh: lang.code == 'he' ? () => actions?.add('geresh') : null,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a letter key emits its symbol', (tester) async {
    final emitted = <int>[];
    await tester.pumpWidget(keyboard(layout: Languages.he.keyboardLayouts.first, emitted: emitted));
    await tester.tap(find.text('א'));
    await tester.pump();
    await tester.tap(find.text('ש'));
    await tester.pump();
    expect(emitted, [0, 20]);
  });

  testWidgets('final-form keys show the final glyph but emit the base symbol', (tester) async {
    final emitted = <int>[];
    final standard = Languages.he.keyboardLayouts.firstWhere((l) => l.id == 'standard');
    await tester.pumpWidget(keyboard(layout: standard, emitted: emitted));
    expect(find.text('ם'), findsOneWidget);
    expect(find.text('ך'), findsOneWidget);
    await tester.tap(find.text('ם'));
    await tester.pump();
    await tester.tap(find.text('ך'));
    await tester.pump();
    await tester.tap(find.text('ץ'));
    await tester.pump();
    expect(emitted, [12, 10, 17], reason: 'ם→מ, ך→כ, ץ→צ');
  });

  testWidgets('keys are at least 48 dp tall and carry letter names for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    final emitted = <int>[];
    await tester.pumpWidget(keyboard(layout: Languages.he.keyboardLayouts.first, emitted: emitted));
    final keyBox = find.ancestor(of: find.text('א'), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(keyBox).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('האות אלף'), findsOneWidget);
    expect(find.bySemanticsLabel('מחיקה'), findsOneWidget);
    expect(find.bySemanticsLabel('גרש'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('action keys call their callbacks', (tester) async {
    final semantics = tester.ensureSemantics();
    final emitted = <int>[];
    final actions = <String>[];
    await tester.pumpWidget(keyboard(layout: Languages.he.keyboardLayouts.first, emitted: emitted, actions: actions));
    await tester.tap(find.bySemanticsLabel('מחיקה'));
    await tester.tap(find.bySemanticsLabel('הבאה'));
    await tester.tap(find.bySemanticsLabel('רמז'));
    await tester.tap(find.bySemanticsLabel('ביטול'));
    await tester.tap(find.bySemanticsLabel('גרש'));
    await tester.pump();
    expect(actions, ['backspace', 'next', 'hint', 'undo', 'geresh']);
    expect(emitted, isEmpty);
    semantics.dispose();
  });

  testWidgets('English QWERTY has no geresh key and emits A–Z symbols', (tester) async {
    final semantics = tester.ensureSemantics();
    final emitted = <int>[];
    final actions = <String>[];
    await tester.pumpWidget(keyboard(
      layout: Languages.en.keyboardLayouts.first,
      emitted: emitted,
      actions: actions,
      lang: Languages.en,
    ));
    expect(find.bySemanticsLabel('גרש'), findsNothing);
    await tester.tap(find.text('Q'));
    await tester.tap(find.text('Z'));
    await tester.pump();
    expect(emitted, [16, 25]);
    semantics.dispose();
  });
}
