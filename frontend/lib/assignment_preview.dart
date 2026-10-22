import 'package:flutter/material.dart';

import 'pages/common.dart';
import 'widgets/assignment_view.dart';

/// Standalone preview of [AssignmentView] with a sample assignment, no backend needed:
///   flutter run -t lib/assignment_preview.dart
void main() {
  runApp(MaterialApp(
    title: 'Assignment preview',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    darkTheme: ThemeData(
      colorScheme:
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
    ),
    home: const AssignmentPreviewPage(),
  ));
}

const sampleAssignment = AssignmentSpec(
  title: 'Homework 3: Sorting & Complexity',
  description: 'Answer every question. You can resubmit as many times as you '
      'like before the due date.',
  items: [
    TextBlock(
      id: 'intro',
      title: 'Before you start',
      text: 'Questions 1–2 cover asymptotic analysis. Question 3 asks you to '
          'explain your reasoning in your own words, and question 4 is your '
          'code or written work as a PDF.',
    ),
    MultipleChoiceQuestion(
      id: 'q1',
      title: 'Worst-case running time of quicksort',
      prompt: 'Assume the pivot is always the first element.',
      points: 2,
      options: ['O(n)', 'O(n log n)', 'O(n²)', 'O(2ⁿ)'],
    ),
    MultipleChoiceQuestion(
      id: 'q2',
      title: 'Which sorts are stable?',
      points: 3,
      selectMultiple: true,
      options: ['Merge sort', 'Heap sort', 'Insertion sort', 'Quicksort (Lomuto)'],
    ),
    FreeResponseQuestion(
      id: 'q3',
      title: 'Why does merge sort need extra memory?',
      prompt: 'A few sentences is enough.',
      points: 5,
      maxLength: 500,
    ),
    FileUploadQuestion(
      id: 'q4',
      title: 'Upload your work',
      prompt: 'Your source code or a scan of handwritten work.',
      points: 10,
      allowedExtensions: ['pdf', 'py', 'java', 'png', 'jpg'],
      maxFiles: 3,
    ),
    FreeResponseQuestion(
      id: 'q5',
      title: 'Anything you want the grader to know?',
      required: false,
      lines: 2,
    ),
  ],
);

class AssignmentPreviewPage extends StatefulWidget {
  const AssignmentPreviewPage({super.key});

  @override
  State<AssignmentPreviewPage> createState() => _AssignmentPreviewPageState();
}

class _AssignmentPreviewPageState extends State<AssignmentPreviewPage> {
  /// Bumped by "Done" to start over with a fresh form.
  int _run = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assignment preview')),
      body: PageWidth(
        child: AssignmentView(
          key: ValueKey(_run),
          assignment: sampleAssignment,
          onSubmit: (_) => Future.delayed(const Duration(milliseconds: 1200)),
          onDone: () => setState(() => _run++),
        ),
      ),
    );
  }
}
