import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/common.dart' show formatSize;
import 'conversion_picker.dart';
import 'ui.dart';

// ---------------------------------------------------------------------------
// Model: what a Gradescope assignment is made of.
// ---------------------------------------------------------------------------

class AssignmentSpec {
  const AssignmentSpec({required this.title, this.description, required this.items});

  final String title;
  final String? description;
  final List<AssignmentItem> items;

  List<Question> get questions => items.whereType<Question>().toList();

  num get totalPoints => questions.fold<num>(0, (sum, q) => sum + (q.points ?? 0));
}

sealed class AssignmentItem {
  const AssignmentItem({required this.id});

  final String id;
}

/// Instructions or context between questions. Nothing to answer.
class TextBlock extends AssignmentItem {
  const TextBlock({required super.id, this.title, required this.text});

  final String? title;
  final String text;
}

sealed class Question extends AssignmentItem {
  const Question({
    required super.id,
    required this.title,
    this.prompt,
    this.points,
    this.required = true,
  });

  final String title;
  final String? prompt;
  final num? points;
  final bool required;
}

class MultipleChoiceQuestion extends Question {
  const MultipleChoiceQuestion({
    required super.id,
    required super.title,
    super.prompt,
    super.points,
    super.required,
    required this.options,
    this.selectMultiple = false,
  });

  final List<String> options;

  /// Checkboxes ("select all that apply") instead of radio buttons.
  final bool selectMultiple;
}

class FreeResponseQuestion extends Question {
  const FreeResponseQuestion({
    required super.id,
    required super.title,
    super.prompt,
    super.points,
    super.required,
    this.lines = 4,
    this.maxLength,
    this.hint,
  });

  final int lines;
  final int? maxLength;
  final String? hint;
}

class FileUploadQuestion extends Question {
  const FileUploadQuestion({
    required super.id,
    required super.title,
    super.prompt,
    super.points,
    super.required,
    this.allowedExtensions,
    this.maxFiles,
    this.existingFiles = const [],
  });

  /// Lowercase, without the dot. Null accepts anything.
  final List<String>? allowedExtensions;
  final int? maxFiles;

  /// Names of files already uploaded in an earlier submission. They count as
  /// an answer; they're listed but can't be removed from here.
  final List<String> existingFiles;
}

/// The student's answers, keyed by question id.
class AssignmentAnswers extends ChangeNotifier {
  final _choices = <String, Set<int>>{};
  final _text = <String, String>{};
  final _files = <String, List<PlatformFile>>{};
  final _conversions = <String, Conversion>{};

  Set<int> choicesFor(String id) => Set.unmodifiable(_choices[id] ?? const <int>{});
  String textFor(String id) => _text[id] ?? '';
  List<PlatformFile> filesFor(String id) =>
      List.unmodifiable(_files[id] ?? const <PlatformFile>[]);
  Conversion conversionFor(String id) => _conversions[id] ?? const NoConversion();

  bool isAnswered(Question q) => switch (q) {
        MultipleChoiceQuestion() => _choices[q.id]?.isNotEmpty ?? false,
        FreeResponseQuestion() => textFor(q.id).trim().isNotEmpty,
        FileUploadQuestion() =>
          (_files[q.id]?.isNotEmpty ?? false) || q.existingFiles.isNotEmpty,
      };

  void toggleChoice(MultipleChoiceQuestion q, int option) {
    final current = _choices.putIfAbsent(q.id, () => {});
    if (q.selectMultiple) {
      if (!current.remove(option)) current.add(option);
    } else {
      current
        ..clear()
        ..add(option);
    }
    notifyListeners();
  }

  void setText(String id, String value) {
    _text[id] = value;
    notifyListeners();
  }

  /// Adds files, keeping only the newest [FileUploadQuestion.maxFiles].
  void addFiles(FileUploadQuestion q, Iterable<PlatformFile> files) {
    final current = _files.putIfAbsent(q.id, () => [])..addAll(files);
    final max = q.maxFiles;
    if (max != null && current.length > max) {
      current.removeRange(0, current.length - max);
    }
    _conversions[q.id] = suggestConversion(conversionFor(q.id), current);
    notifyListeners();
  }

  void setConversion(String id, Conversion conversion) {
    _conversions[id] = conversion;
    notifyListeners();
  }

  void removeFile(String id, PlatformFile file) {
    _files[id]?.remove(file);
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// The widget.
// ---------------------------------------------------------------------------

/// Renders an [AssignmentSpec] as an animated, fill-in-able form.
///
/// Required questions are checked before [onSubmit] runs; if any are missing
/// the button shakes and the page scrolls to the first one. If [onSubmit]
/// throws, its message is shown and the student can try again.
class AssignmentView extends StatefulWidget {
  const AssignmentView({
    super.key,
    required this.assignment,
    required this.onSubmit,
    this.answers,
    this.onDone,
    this.conversionFormats,
    this.banner,
    this.submitLabel = 'Submit',
  });

  final AssignmentSpec assignment;
  final Future<void> Function(AssignmentAnswers answers) onSubmit;

  /// Pass one in to read or prefill answers from outside. Owned by the caller.
  final AssignmentAnswers? answers;

  /// Shows a "Done" button on the success screen when set.
  final VoidCallback? onDone;

  /// Target format -> source extensions. When set, each file upload offers to
  /// convert its files before submitting.
  final Map<String, List<String>>? conversionFormats;

  /// Shown under the title, e.g. what was submitted before.
  final Widget? banner;

  /// The submit button's verb, e.g. "Resubmit".
  final String submitLabel;

  @override
  State<AssignmentView> createState() => _AssignmentViewState();
}

class _AssignmentViewState extends State<AssignmentView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AssignmentAnswers _answers = widget.answers ?? AssignmentAnswers();
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
  final _keys = <String, GlobalKey>{};
  bool _showErrors = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // The Scaffold strips the keyboard inset from its body's MediaQuery,
    // so read it off the view itself.
    final open = View.of(context).viewInsets.bottom > 0;
    if (open != _keyboardOpen) setState(() => _keyboardOpen = open);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shake.dispose();
    if (widget.answers == null) _answers.dispose();
    super.dispose();
  }

  List<Question> get _missing => [
        for (final q in widget.assignment.questions)
          if (q.required && !_answers.isAnswered(q)) q,
      ];

  Future<void> _submit() async {
    final missing = _missing;
    if (missing.isNotEmpty) {
      setState(() => _showErrors = true);
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      final target = _keys[missing.first.id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            alignment: 0.1);
      }
      return;
    }
    final formats = widget.conversionFormats;
    if (formats != null) {
      for (final q in widget.assignment.questions.whereType<FileUploadQuestion>()) {
        final problem =
            conversionProblem(_answers.conversionFor(q.id), _answers.filesFor(q.id), formats);
        if (problem == null) continue;
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
        final target = _keys[q.id]?.currentContext;
        if (target != null) Scrollable.ensureVisible(target, alignment: 0.1);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_answers);
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _submitted = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
      ),
      child: _submitted
          ? _SuccessPanel(
              key: const ValueKey('done'),
              title: widget.assignment.title,
              answered:
                  widget.assignment.questions.where(_answers.isAnswered).length,
              total: widget.assignment.questions.length,
              onDone: widget.onDone,
            )
          : ListenableBuilder(
              key: const ValueKey('form'),
              listenable: _answers,
              builder: (context, _) => _buildForm(context),
            ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final a = widget.assignment;
    final questions = a.questions;
    final answered = questions.where(_answers.isAnswered).length;
    final missing = _missing;
    final numbers = {for (final (i, q) in questions.indexed) q.id: i + 1};

    return Column(
      children: [
        _ProgressHeader(answered: answered, total: questions.length),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(index: 0, child: _AssignmentHeader(assignment: a)),
                if (widget.banner case final banner?)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Entrance(index: 0, child: banner),
                  ),
                for (final (i, item) in a.items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Entrance(
                      index: i + 1,
                      child: switch (item) {
                        TextBlock() => _TextBlockCard(block: item),
                        Question() => _QuestionCard(
                            key: _keys.putIfAbsent(item.id, GlobalKey.new),
                            number: numbers[item.id]!,
                            question: item,
                            answered: _answers.isAnswered(item),
                            showError: _showErrors &&
                                item.required &&
                                !_answers.isAnswered(item),
                            child: _questionBody(item),
                          ),
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        _SubmitBar(
          hidden: _keyboardOpen,
          shake: _shake,
          submitting: _submitting,
          ready: missing.isEmpty,
          missing: _showErrors ? missing.length : 0,
          label: widget.submitLabel,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _questionBody(Question q) => switch (q) {
        MultipleChoiceQuestion() => _ChoiceList(
            question: q,
            selected: _answers.choicesFor(q.id),
            onToggle: (i) => _answers.toggleChoice(q, i),
          ),
        FreeResponseQuestion() => _FreeResponseField(
            question: q,
            initial: _answers.textFor(q.id),
            onChanged: (v) => _answers.setText(q.id, v),
          ),
        FileUploadQuestion() => _FileUploadField(
            question: q,
            files: _answers.filesFor(q.id),
            onAdd: (files) => _answers.addFiles(q, files),
            onRemove: (f) => _answers.removeFile(q.id, f),
            conversion: _answers.conversionFor(q.id),
            conversionFormats: widget.conversionFormats,
            onConversionChanged:
                _submitting ? null : (c) => _answers.setConversion(q.id, c),
          ),
      };
}

// ---------------------------------------------------------------------------
// Page chrome.
// ---------------------------------------------------------------------------

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.answered, required this.total});

  final int answered, total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = answered == total;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _SlideSwitcher(
                      child: Text('$answered of $total answered',
                          key: ValueKey(answered),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: done
                      ? Icon(Icons.check_circle,
                          key: const ValueKey('done'), size: 20, color: scheme.primary)
                      : Text(
                          '${total == 0 ? 100 : (answered * 100 / total).round()}%',
                          key: const ValueKey('pct'),
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(end: total == 0 ? 1 : answered / total),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: value, minHeight: 6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentHeader extends StatelessWidget {
  const _AssignmentHeader({required this.assignment});

  final AssignmentSpec assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = assignment.questions.length;
    final points = assignment.totalPoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(assignment.title,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (assignment.description != null) ...[
          const SizedBox(height: 6),
          Text(assignment.description!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(icon: Icons.quiz_outlined, label: '$count ${count == 1 ? 'question' : 'questions'}'),
            if (points > 0) Pill(icon: Icons.star_outline, label: '${_points(points)} total'),
          ],
        ),
      ],
    );
  }
}

String _points(num p) {
  final s = p == p.roundToDouble() ? p.toInt().toString() : p.toString();
  return '$s ${p == 1 ? 'pt' : 'pts'}';
}

/// Swaps text by sliding the new value up from below.
class _SlideSwitcher extends StatelessWidget {
  const _SlideSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => ClipRect(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Cards.
// ---------------------------------------------------------------------------

class _TextBlockCard extends StatelessWidget {
  const _TextBlockCard({required this.block});

  final TextBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: scheme.tertiary, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.title != null) ...[
            Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(block.title!,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(block.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.number,
    required this.question,
    required this.answered,
    required this.showError,
    required this.child,
  });

  final int number;
  final Question question;
  final bool answered, showError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = showError ? scheme.error : scheme.primary;
    final lit = showError || answered;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: lit ? accent.withValues(alpha: 0.7) : scheme.outlineVariant,
          width: lit ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: lit ? 0.14 : 0),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NumberBadge(number: number, answered: answered, error: showError),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(question.title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (question.prompt != null) ...[
                      const SizedBox(height: 6),
                      Text(question.prompt!, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (question.points != null) Pill(label: _points(question.points!)),
                  if (!question.required)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Optional',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: showError
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('This question needs an answer.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.error)),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Question number that flips to a check mark once answered.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge(
      {required this.number, required this.answered, required this.error});

  final int number;
  final bool answered, error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = answered
        ? (scheme.primary, scheme.onPrimary)
        : error
            ? (scheme.errorContainer, scheme.onErrorContainer)
            : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: -0.25, end: 0.0).animate(anim),
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: answered
            ? Icon(Icons.check_rounded, key: const ValueKey('check'), size: 20, color: fg)
            : Text('$number',
                key: const ValueKey('number'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Pinned below the questions. Tucks away while the keyboard is up so the
/// text field keeps the room; dismissing the keyboard brings it back.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.hidden,
    required this.shake,
    required this.submitting,
    required this.ready,
    required this.missing,
    required this.label,
    required this.onPressed,
  });

  final bool hidden, submitting, ready;
  final String label;
  final Animation<double> shake;

  /// Required questions left to point out; 0 hides the hint.
  final int missing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: hidden ? 0 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: missing > 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            missing == 1
                                ? 'Answer 1 more required question to submit.'
                                : 'Answer $missing more required questions to submit.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.error),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                ShakeTransition(
                  animation: shake,
                  child: PillButton(
                    label: ready ? '$label assignment' : label,
                    icon: Icons.send_rounded,
                    busy: submitting,
                    busyLabel: 'Submitting…',
                    glow: ready,
                    onPressed: onPressed,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multiple choice.
// ---------------------------------------------------------------------------

class _ChoiceList extends StatelessWidget {
  const _ChoiceList(
      {required this.question, required this.selected, required this.onToggle});

  final MultipleChoiceQuestion question;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (question.selectMultiple)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Select all that apply',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        for (final (i, option) in question.options.indexed)
          _ChoiceTile(
            letter: String.fromCharCode(65 + i),
            label: option,
            selected: selected.contains(i),
            multiple: question.selectMultiple,
            onTap: () => onToggle(i),
          ),
      ],
    );
  }
}

class _ChoiceTile extends StatefulWidget {
  const _ChoiceTile({
    required this.letter,
    required this.label,
    required this.selected,
    required this.multiple,
    required this.onTap,
  });

  final String letter, label;
  final bool selected, multiple;
  final VoidCallback onTap;

  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: !widget.multiple,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : _pressed
                      ? scheme.surfaceContainerHigh
                      : scheme.surfaceContainerLow,
              borderRadius: radius,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap();
                },
                onHighlightChanged: (v) => setState(() => _pressed = v),
                child: Padding(
                  // 1px less when the border is 2px, so the text doesn't shift.
                  padding: EdgeInsets.all(selected ? 11 : 12),
                  child: Row(
                    children: [
                      _ChoiceIndicator(
                          letter: widget.letter,
                          selected: selected,
                          multiple: widget.multiple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(widget.label,
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lettered circle (radio) or rounded square (checkbox) that pops a check in.
class _ChoiceIndicator extends StatelessWidget {
  const _ChoiceIndicator(
      {required this.letter, required this.selected, required this.multiple});

  final String letter;
  final bool selected, multiple;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(multiple ? 8 : 15),
        border: Border.all(
            color: selected ? scheme.primary : scheme.outline, width: 1.5),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.elasticOut,
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
        child: selected
            ? Icon(Icons.check_rounded,
                key: const ValueKey('check'), size: 18, color: scheme.onPrimary)
            : Text(letter,
                key: const ValueKey('letter'),
                style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Free response.
// ---------------------------------------------------------------------------

class _FreeResponseField extends StatefulWidget {
  const _FreeResponseField(
      {required this.question, required this.initial, required this.onChanged});

  final FreeResponseQuestion question;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_FreeResponseField> createState() => _FreeResponseFieldState();
}

class _FreeResponseFieldState extends State<_FreeResponseField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = widget.question;
    final text = _controller.text;
    final words = RegExp(r'\S+').allMatches(text).length;
    final max = q.maxLength;
    final used = max == null ? 0.0 : text.characters.length / max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusGlow(
          child: TextField(
            controller: _controller,
            minLines: q.lines,
            maxLines: q.lines * 3,
            maxLength: max,
            textCapitalization: TextCapitalization.sentences,
            // Tapping anywhere else (a choice, the background) closes the keyboard.
            onTapOutside: unfocusOnTapOutside,
            buildCounter: (_, {required currentLength, required isFocused, required maxLength}) =>
                null,
            onChanged: (v) {
              widget.onChanged(v);
              setState(() {});
            },
            decoration: softInputDecoration(context,
                hintText: q.hint ?? 'Type your answer…'),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _SlideSwitcher(
              child: Text('$words ${words == 1 ? 'word' : 'words'}',
                  key: ValueKey(words),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            if (max != null) ...[
              const SizedBox(width: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(end: used),
                duration: const Duration(milliseconds: 200),
                builder: (context, v, _) => SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    value: v.clamp(0, 1),
                    strokeWidth: 2.5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: Color.lerp(scheme.primary, scheme.error,
                        ((v - 0.8) / 0.2).clamp(0, 1)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${text.characters.length} / $max',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: used >= 1 ? scheme.error : scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// File upload.
// ---------------------------------------------------------------------------

class _FileUploadField extends StatefulWidget {
  const _FileUploadField({
    required this.question,
    required this.files,
    required this.onAdd,
    required this.onRemove,
    this.conversion = const NoConversion(),
    this.conversionFormats,
    this.onConversionChanged,
  });

  final FileUploadQuestion question;
  final List<PlatformFile> files;
  final ValueChanged<List<PlatformFile>> onAdd;
  final ValueChanged<PlatformFile> onRemove;
  final Conversion conversion;

  /// Null hides the conversion picker.
  final Map<String, List<String>>? conversionFormats;
  final ValueChanged<Conversion>? onConversionChanged;

  @override
  State<_FileUploadField> createState() => _FileUploadFieldState();
}

class _FileUploadFieldState extends State<_FileUploadField>
    with SingleTickerProviderStateMixin {
  /// Drives the "marching ants" border while pressed.
  late final _march =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _pressed = false;

  @override
  void dispose() {
    _march.dispose();
    super.dispose();
  }

  void _setPressed(bool v) {
    setState(() => _pressed = v);
    if (v && !MediaQuery.disableAnimationsOf(context)) {
      _march.repeat();
    } else {
      _march.stop();
    }
  }

  Future<void> _pick() async {
    final exts = widget.question.allowedExtensions;
    final picked = await FilePicker.pickFiles(
      dialogTitle: widget.question.title,
      type: exts == null ? FileType.any : FileType.custom,
      allowedExtensions: exts,
    );
    if (picked.isEmpty || !mounted) return;
    // Some platforms ignore the extension filter, so check again.
    final ok = exts == null
        ? picked
        : picked
            .where((f) => exts.contains((f.extension ?? '').toLowerCase()))
            .toList();
    if (ok.length < picked.length) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Only ${exts!.map((e) => '.$e').join(', ')} files are accepted.')));
    }
    if (ok.isNotEmpty) {
      HapticFeedback.lightImpact();
      widget.onAdd(ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = widget.question;
    final files = widget.files;
    final radius = BorderRadius.circular(16);
    final exts = q.allowedExtensions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _march,
          builder: (context, child) => CustomPaint(
            painter: _DashedBorderPainter(
              color: _pressed ? scheme.primary : scheme.outline,
              phase: _march.value,
              radius: 16,
            ),
            child: child,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: _pick,
              onHighlightChanged: _setPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: files.isEmpty ? 28 : 16),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: scheme.primary.withValues(alpha: _pressed ? 0.07 : 0.02),
                ),
                child: Column(
                  children: [
                    AnimatedSlide(
                      offset: Offset(0, _pressed ? -0.12 : 0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: AnimatedScale(
                        scale: _pressed ? 1.15 : 1,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: Icon(Icons.cloud_upload_outlined,
                            size: files.isEmpty ? 40 : 28, color: scheme.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      files.isEmpty
                          ? 'Tap to choose ${q.maxFiles == 1 ? 'a file' : 'files'}'
                          : q.maxFiles == 1
                              ? 'Replace file'
                              : 'Add more files',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (exts != null || q.maxFiles != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (exts != null) exts.map((e) => '.$e').join('  '),
                          if (q.maxFiles != null && q.maxFiles! > 1)
                            'up to ${q.maxFiles} files',
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in q.existingFiles) _ExistingFileTile(name: name),
              for (final f in files)
                Entrance(
                  key: ObjectKey(f),
                  index: 0,
                  child: _FileTile(file: f, onRemove: () => widget.onRemove(f)),
                ),
            ],
          ),
        ),
        if (widget.conversionFormats case final formats?) ...[
          const SizedBox(height: 12),
          ConversionPicker(
            conversion: widget.conversion,
            files: files,
            formats: formats,
            onChanged: widget.onConversionChanged,
            label: 'Before submitting',
          ),
        ],
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.onRemove});

  final PlatformFile file;
  final VoidCallback onRemove;

  static IconData _icon(String ext) => switch (ext) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'png' || 'jpg' || 'jpeg' || 'heic' || 'heif' || 'webp' || 'gif' =>
          Icons.image_outlined,
        'mp4' || 'mov' || 'm4v' || 'avi' || 'mkv' || 'webm' => Icons.movie_outlined,
        'mp3' || 'm4a' || 'wav' || 'aac' || 'ogg' || 'flac' => Icons.audiotrack_outlined,
        'zip' => Icons.folder_zip_outlined,
        'txt' || 'md' || 'doc' || 'docx' => Icons.description_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = file.lengthSync();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_icon((file.extension ?? '').toLowerCase()),
                size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
                if (size != null)
                  Text(formatSize(size),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// A file from an earlier submission, already on Gradescope.
class _ExistingFileTile extends StatelessWidget {
  const _ExistingFileTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
          ),
          Text('On Gradescope',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(
      {required this.color, required this.phase, required this.radius});

  final Color color;

  /// 0..1, shifts the dashes along the border by one dash+gap period.
  final double phase;
  final double radius;

  static const _dash = 8.0;
  static const _gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75), Radius.circular(radius));
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = (phase - 1) * (_dash + _gap); d < metric.length; d += _dash + _gap) {
        final start = math.max(0.0, d);
        final end = math.min(metric.length, d + _dash);
        if (end > start) canvas.drawPath(metric.extractPath(start, end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.phase != phase || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Success screen.
// ---------------------------------------------------------------------------

class _SuccessPanel extends StatefulWidget {
  const _SuccessPanel({
    super.key,
    required this.title,
    required this.answered,
    required this.total,
    this.onDone,
  });

  final String title;
  final int answered, total;
  final VoidCallback? onDone;

  @override
  State<_SuccessPanel> createState() => _SuccessPanelState();
}

class _SuccessPanelState extends State<_SuccessPanel>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  late final _text = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.7, curve: Curves.easeOutCubic));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 220,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _CelebrationPainter(
                    t: _controller.value,
                    color: scheme.primary,
                    onColor: scheme.onPrimary,
                    confetti: [
                      scheme.primary,
                      scheme.tertiary,
                      scheme.secondary,
                      Colors.amber,
                      Colors.pinkAccent,
                    ],
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: _text,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                    .animate(_text),
                child: Column(
                  children: [
                    Text('Submitted!',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('${widget.answered} of ${widget.total} questions answered',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (widget.onDone != null) ...[
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                          onPressed: widget.onDone, child: const Text('Done')),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ring sweeps in, fills, draws a check, and throws confetti. [t] runs 0..1.
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({
    required this.t,
    required this.color,
    required this.onColor,
    required this.confetti,
  });

  final double t;
  final Color color, onColor;
  final List<Color> confetti;

  static final _particles = () {
    final rng = math.Random(7);
    return [
      for (var i = 0; i < 48; i++)
        (
          angle: rng.nextDouble() * math.pi * 2,
          speed: 55 + rng.nextDouble() * 55,
          spin: (rng.nextDouble() - 0.5) * 12,
          size: 4 + rng.nextDouble() * 5,
          color: i,
        ),
    ];
  }();

  static double _phase(double t, double begin, double end) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = 46.0;

    // Confetti, behind the badge.
    final c = _phase(t, 0.3, 1);
    if (c > 0 && c < 1) {
      final travel = Curves.easeOutCubic.transform(c);
      final paint = Paint();
      for (final p in _particles) {
        final pos = center +
            Offset(math.cos(p.angle), math.sin(p.angle)) * (r * 0.6 + p.speed * travel) +
            Offset(0, 40 * c * c);
        paint.color = confetti[p.color % confetti.length].withValues(alpha: 1 - c);
        canvas
          ..save()
          ..translate(pos.dx, pos.dy)
          ..rotate(p.spin * c)
          ..drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint)
          ..restore();
      }
    }

    // Ring sweeping around.
    final sweep = Curves.easeInOut.transform(_phase(t, 0, 0.3));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      math.pi * 2 * sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Fill pops in with a little overshoot.
    final fill = Curves.easeOutBack.transform(_phase(t, 0.25, 0.45));
    if (fill > 0) {
      canvas.drawCircle(center, r * fill, Paint()..color = color);
    }

    // Check mark draws itself.
    final check = Curves.easeOutCubic.transform(_phase(t, 0.4, 0.62));
    if (check > 0) {
      final path = Path()
        ..moveTo(center.dx - 19, center.dy + 1)
        ..lineTo(center.dx - 5, center.dy + 15)
        ..lineTo(center.dx + 20, center.dy - 13);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * check),
        Paint()
          ..color = onColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) =>
      old.t != t || old.color != color || old.onColor != onColor;
}
