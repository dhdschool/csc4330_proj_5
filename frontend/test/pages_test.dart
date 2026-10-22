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
