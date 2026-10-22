import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/widgets/assignment_view.dart';

const _assignment = AssignmentSpec(
  title: 'Quiz',
  items: [
    TextBlock(id: 'intro', text: 'Read carefully.'),
    MultipleChoiceQuestion(id: 'mc', title: 'Pick one', options: ['Red', 'Blue']),
    FreeResponseQuestion(id: 'fr', title: 'Explain'),
    FreeResponseQuestion(id: 'opt', title: 'Comments', required: false),
  ],
);

Future<AssignmentAnswers> _pump(WidgetTester tester,
    {Future<void> Function(AssignmentAnswers)? onSubmit}) async {
  final answers = AssignmentAnswers();
  addTearDown(answers.dispose);
  tester.view
    ..physicalSize = const Size(800, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AssignmentView(
        assignment: _assignment,
        answers: answers,
        onSubmit: onSubmit ?? (_) async {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  testWidgets('renders text blocks and every question', (tester) async {
    await _pump(tester);

    expect(find.text('Quiz'), findsOneWidget);
    expect(find.text('Read carefully.'), findsOneWidget);
    expect(find.text('Pick one'), findsOneWidget);
    expect(find.text('Red'), findsOneWidget);
    expect(find.text('Explain'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.text('0 of 3 answered'), findsOneWidget);
  });

  testWidgets('answering updates progress', (tester) async {
    final answers = await _pump(tester);

    await tester.tap(find.text('Blue'));
    await tester.pumpAndSettle();
    expect(answers.choicesFor('mc'), {1});
    expect(find.text('1 of 3 answered'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Because reasons');
    await tester.pumpAndSettle();
    expect(answers.textFor('fr'), 'Because reasons');
    expect(find.text('2 words'), findsOneWidget);
  });

  testWidgets('blocks submit until required questions are answered',
      (tester) async {
    var submitted = 0;
    await _pump(tester, onSubmit: (_) async => submitted++);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(submitted, 0);
    expect(find.text('This question needs an answer.'), findsNWidgets(2));
    expect(find.text('Answer 2 more required questions to submit.'), findsOneWidget);

    await tester.tap(find.text('Red'));
    await tester.enterText(find.byType(TextField).first, 'Done');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit assignment'));
    await tester.pumpAndSettle();

    expect(submitted, 1);
    expect(find.text('Submitted!'), findsOneWidget);
  });

  testWidgets('submit bar tucks away while the keyboard is up', (tester) async {
    await _pump(tester);
    expect(find.text('Submit').hitTestable(), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('Submit').hitTestable(), findsNothing);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Submit').hitTestable(), findsOneWidget);
  });

  testWidgets('fits a small phone screen', (tester) async {
    tester.view
      ..physicalSize = const Size(360 * 3, 640 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AssignmentView(assignment: _assignment, onSubmit: (_) async {}),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed submit shows the error and keeps the form',
      (tester) async {
    await _pump(tester, onSubmit: (_) async => throw Exception('Gradescope is down'));

    await tester.tap(find.text('Red'));
    await tester.enterText(find.byType(TextField).first, 'x');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit assignment'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gradescope is down'), findsOneWidget);
    expect(find.text('Submitted!'), findsNothing);
    expect(find.text('Submit assignment'), findsOneWidget);
  });
}
