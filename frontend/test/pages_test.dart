import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api.dart';
import 'package:frontend/pages/assignments_page.dart';
import 'package:frontend/pages/common.dart';
import 'package:frontend/pages/courses_page.dart';
import 'package:frontend/pages/submit_page.dart';
import 'package:frontend/widgets/assignment_view.dart';

/// Hands back [files] instead of opening a file dialog.
class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.files);

  final List<PlatformFile> files;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      files;
}

final class _FakeFile extends PlatformFile {
  _FakeFile(this.name);

  @override
  final String name;

  @override
  Uri get uri => Uri.file('/tmp/$name');

  @override
  get xFile => throw UnimplementedError(); // type inferred: XFile isn't exported

  @override
  int? lengthSync() => 1024;

  @override
  Future<int?> length() async => 1024;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(1024);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(1024));
}

Widget _app(Widget body) => MaterialApp(home: Scaffold(body: body));

/// Phone-sized screen so overflows show up as test failures.
void _phone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(360 * 3, 740 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Assignment _assignment(String name,
        {Duration? dueIn, Duration? lateIn, String status = 'No Submission',
        String? grade, String? maxGrade, bool canSubmit = true}) =>
    Assignment.fromJson({
      'assignment_id': canSubmit ? name : null,
      'name': name,
      'due_date': dueIn == null ? null : DateTime.now().add(dueIn).toIso8601String(),
      'late_due_date':
          lateIn == null ? null : DateTime.now().add(lateIn).toIso8601String(),
      'submissions_status': status,
      'grade': grade,
      'max_grade': maxGrade,
    });

void main() {
  group('AsyncList', () {
    Widget list(Future<List<String>> future, {VoidCallback? onRetry}) => _app(
          AsyncList<String>(
            future: future,
            onRetry: onRetry ?? () {},
            emptyText: 'Nothing here',
            builder: (context, items) => [for (final s in items) Text(s)],
          ),
        );

    testWidgets('shows a skeleton, then the rows', (tester) async {
      final done = Completer<List<String>>();
      await tester.pumpWidget(list(done.future));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);

      done.complete(['one', 'two']);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
    });

    testWidgets('shows the empty message', (tester) async {
      await tester.pumpWidget(list(Future.value([])));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('shows the error and retries', (tester) async {
      var retries = 0;
      final failed = Completer<List<String>>();
      await tester.pumpWidget(list(failed.future, onRetry: () => retries++));
      failed.completeError(ApiException(502, 'Gradescope is down'));
      await tester.pumpAndSettle();

      expect(find.text('Gradescope is down'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });
  });

  testWidgets('course cards fit a phone screen', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(ListView(children: [
      CourseCard(
        course: Course.fromJson({
          'id': '123',
          'role': 'instructor',
          'name': 'CSC 4330 Software Systems Development and Design',
          'full_name': 'Software Systems Development and Design, Section 2, Fall',
          'semester': 'Fall',
          'year': 2026,
        }),
        onTap: () {},
      ),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CSC'), findsOneWidget);
    expect(find.text('Instructor'), findsOneWidget);
  });

  testWidgets('assignment cards fit a phone screen in every state', (tester) async {
    _phone(tester);
    final long = 'Homework 7: Dynamic Programming, Memoization, and Other Things';
    await tester.pumpWidget(_app(ListView(children: [
      AssignmentCard(
          assignment: _assignment(long, dueIn: const Duration(hours: 5, minutes: 30)),
          onTap: () {}),
      AssignmentCard(
          assignment: _assignment(long, dueIn: const Duration(days: 9, hours: 1)),
          onTap: () {}),
      AssignmentCard(
          assignment: _assignment(long,
              dueIn: const Duration(days: -1), lateIn: const Duration(days: 2)),
          onTap: () {}),
      AssignmentCard(
          assignment: _assignment(long,
              dueIn: const Duration(days: -5), status: 'Graded', grade: '18.5', maxGrade: '20')),
      AssignmentCard(assignment: _assignment(long, canSubmit: false)),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('5 h left'), findsOneWidget);
    expect(find.text('9 days left'), findsOneWidget);
    expect(find.textContaining('Late until'), findsOneWidget);
    expect(find.bySemanticsLabel('Grade 18.5 out of 20'), findsOneWidget);
  });

  testWidgets('a suggested conversion works before the format list loads',
      (tester) async {
    // The test HTTP client fails every request, so /convert/formats never loads.
    final picker = FilePickerPlatform.instance;
    addTearDown(() => FilePickerPlatform.instance = picker);
    FilePickerPlatform.instance = _FakePicker([_FakeFile('clip.mov')]);

    await tester.pumpWidget(MaterialApp(
      home: SubmitPage(
        course: Course.fromJson({'id': '1', 'name': 'CSC 4330'}),
        assignment: _assignment('Video demo', dueIn: const Duration(days: 2)),
      ),
    ));
    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Convert each file to .mp4'), findsOneWidget);
    expect(find.text('Gradescope will receive: clip.mp4'), findsOneWidget);
  });

  testWidgets('submit page still works when the questions fail to load',
      (tester) async {
    // The test HTTP client fails every request, so the questions never load.
    _phone(tester);
    await tester.pumpWidget(MaterialApp(
      home: SubmitPage(
        course: Course.fromJson({'id': '1', 'name': 'CSC 4330'}),
        assignment: _assignment('Quiz 1', dueIn: const Duration(days: 2)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining("Couldn't load the questions"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Add files'), findsOneWidget);
  });

  test('OnlineQuestion.fromJson reads what the backend sends', () {
    final q = OnlineQuestion.fromJson({
      'id': 11, 'parent_id': null, 'index': 1, 'title': 'Pick one', 'weight': '2.0',
      'content': [
        {'type': 'text', 'value': 'Which sort is stable?'},
        {'type': 'radio_input', 'choices': [{'value': 'Merge sort'}, {'value': 'Heap sort'}]},
        {'type': 'something_new', 'extra': 1},
      ],
    });
    expect(q.id, '11');
    expect(q.index, '1');
    expect(q.parentId, isNull);
    expect(q.blocks.map((b) => b.type),
        ['text', 'radio_input', 'something_new']);
    expect(q.blocks[0].text, 'Which sort is stable?');
    expect(q.blocks[1].choices, ['Merge sort', 'Heap sort']);
  });

  group('assignmentSpec', () {
    // Shaped like Project 5: one question holding several inputs.
    final project = OnlineQuestion.fromJson({
      'id': 7, 'parent_id': null, 'index': 1, 'title': 'Project info', 'weight': '100.0',
      'content': [
        {'type': 'text', 'value': 'Enter github URL:'},
        {'type': 'free_response_input'},
        {'type': 'text', 'value': 'Largest gap with no commits?'},
        {'type': 'radio_input', 'choices': [{'value': '1'}, {'value': '2'}, {'value': '8+'}]},
        {'type': 'text', 'value': 'Upload a video demo:'},
        {'type': 'file_upload_input'},
      ],
    });

    test('turns each input into a question titled by the text above it', () {
      final spec = assignmentSpec('Project 5', [project]);
      expect(spec.description, 'Worth 100 pts.');
      expect(spec.items.whereType<TextBlock>(), isEmpty);
      final [url, gap, video] = spec.questions;
      expect((url as FreeResponseQuestion).title, 'Enter github URL:');
      expect(url.id, '7/0');
      expect((gap as MultipleChoiceQuestion).options, ['1', '2', '8+']);
      expect(gap.id, '7/1');
      expect(video, isA<FileUploadQuestion>());
      expect(video.id, '7/2');
    });

    testWidgets('lets you pick a choice and type an answer', (tester) async {
      _phone(tester);
      final answers = AssignmentAnswers();
      addTearDown(answers.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssignmentView(
            assignment: assignmentSpec('Project 5', [project]),
            answers: answers,
            onSubmit: (_) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'https://github.com/me/app');
      await tester.ensureVisible(find.text('8+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8+'));
      await tester.pumpAndSettle();
      expect(answers.textFor('7/0'), 'https://github.com/me/app');
      expect(answers.choicesFor('7/1'), {2});
    });

    testWidgets('a past submission is filled in, with a banner and Resubmit',
        (tester) async {
      _phone(tester);
      final content = AssignmentContent.fromJson({
        'questions': const [],
        'answers': {'7/0': 'https://github.com/me/app', '7/1': '8+', '7/9': 'stale'},
        'files': {'7/2': ['demo.mp4']},
        'submission': {
          'id': 9,
          'created_at': '2026-10-22T13:00:00-05:00',
          'score': '90',
          'total_points': '100.0',
          'url': 'https://www.gradescope.com/courses/1/assignments/2/submissions/9',
        },
      });
      final spec = assignmentSpec('Project 5', [project], existingFiles: content.files);
      final answers = prefilledAnswers(spec, content.answers);
      addTearDown(answers.dispose);

      expect(answers.textFor('7/0'), 'https://github.com/me/app');
      expect(answers.choicesFor('7/1'), {2}); // "8+"
      expect(answers.isAnswered(spec.questions[2]), isTrue); // the uploaded video

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssignmentView(
            assignment: spec,
            answers: answers,
            banner: SubmissionBanner(
                submission: content.submission,
                assignment: _assignment('Project 5', status: 'Submitted')),
            submitLabel: 'Resubmit',
            onSubmit: (_) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('90 / 100 pts'), findsOneWidget);
      expect(find.text('View on Gradescope'), findsOneWidget);
      expect(find.text('Resubmit assignment'), findsOneWidget);
      expect(find.text('https://github.com/me/app'), findsOneWidget);
      await tester.ensureVisible(find.text('demo.mp4'));
      expect(find.text('On Gradescope'), findsOneWidget);
    });

    testWidgets('each file upload offers a conversion', (tester) async {
      _phone(tester);
      final picker = FilePickerPlatform.instance;
      addTearDown(() => FilePickerPlatform.instance = picker);
      FilePickerPlatform.instance = _FakePicker([_FakeFile('demo.mov')]);
      final answers = AssignmentAnswers();
      addTearDown(answers.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssignmentView(
            assignment: assignmentSpec('Project 5', [project]),
            answers: answers,
            conversionFormats: const {'mp4': ['mov'], 'pdf': ['png', 'jpg']},
            onSubmit: (_) async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Before submitting'), findsOneWidget); // one upload question

      await tester.ensureVisible(find.textContaining('Tap to choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Tap to choose'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(answers.conversionFor('7/2').key, 'to:mp4');
      expect(find.text('Gradescope will receive: demo.mp4'), findsOneWidget);
    });
  });

  test('timeLeft', () {
    expect(timeLeft(const Duration(seconds: 20)), '1 min left');
    expect(timeLeft(const Duration(minutes: 45)), '45 min left');
    expect(timeLeft(const Duration(hours: 5, minutes: 59)), '5 h left');
    expect(timeLeft(const Duration(hours: 30)), '1 day left');
    expect(timeLeft(const Duration(days: 4)), '4 days left');
  });

  test('courseInitials', () {
    expect(courseInitials('CSC 4330'), 'CSC');
    expect(courseInitials('MATH 1550 Calculus'), 'MATH');
    expect(courseInitials('Intro to Programming'), 'IT');
    expect(courseInitials('  '), '?');
  });
}
