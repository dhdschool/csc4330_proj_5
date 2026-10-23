import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../widgets/assignment_view.dart';
import '../widgets/conversion_picker.dart';
import 'assignments_page.dart' show formatDate, isPastDue;
import 'common.dart';

class SubmitPage extends StatefulWidget {
  const SubmitPage({super.key, required this.course, required this.assignment});

  final Course course;
  final Assignment assignment;

  @override
  State<SubmitPage> createState() => _SubmitPageState();
}

class _SubmitPageState extends State<SubmitPage> {
  final List<PlatformFile> _files = [];
  Conversion _conversion = const NoConversion();
  Map<String, List<String>> _formats = {};
  bool _submitting = false;
  late Future<AssignmentContent> _content = _loadContent();

  /// Built once the content loads, so answers typed in survive rebuilds.
  AssignmentSpec? _spec;
  AssignmentAnswers? _answers;

  Future<AssignmentContent> _loadContent() => Api.instance
      .content(widget.course.id, widget.assignment.id!); // set whenever this page opens

  void _reload() => setState(() {
        _answers?.dispose();
        _spec = null;
        _answers = null;
        _content = _loadContent();
      });

  /// Gradescope lists it as submitted, from the assignments list or the page itself.
  bool _hasSubmission(AssignmentContent content) {
    final a = widget.assignment;
    return content.submission != null ||
        a.grade != null ||
        (a.status.isNotEmpty && a.status != 'No Submission');
  }

  Future<void> _saveAnswers(AssignmentAnswers answers, AssignmentSpec spec) =>
      Api.instance.saveAnswers(
        widget.course.id,
        widget.assignment.id!,
        text: {
          for (final q in spec.questions.whereType<FreeResponseQuestion>())
            if (answers.textFor(q.id).isNotEmpty) q.id: answers.textFor(q.id),
        },
        choices: {
          for (final q in spec.questions.whereType<MultipleChoiceQuestion>())
            if (answers.choicesFor(q.id).isNotEmpty)
              q.id: q.options[answers.choicesFor(q.id).first],
        },
        files: {
          for (final q in spec.questions.whereType<FileUploadQuestion>())
            if (answers.filesFor(q.id).isNotEmpty) q.id: answers.filesFor(q.id),
        },
        conversions: {
          for (final q in spec.questions.whereType<FileUploadQuestion>())
            if (answers.filesFor(q.id).isNotEmpty) q.id: answers.conversionFor(q.id).key,
        },
      );

  @override
  void dispose() {
    _answers?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Api.instance.formats().then((f) {
      if (mounted) setState(() => _formats = f);
    }).catchError((_) {
      // Without the list we just skip the local check; the backend still validates.
    });
  }

  /// Why the current files + conversion won't work, or null if they will.
  String? get _problem => _files.isEmpty
      ? 'Add at least one file.'
      : conversionProblem(_conversion, _files, _formats);

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose files');
    if (picked.isEmpty) return;
    setState(() {
      _files.addAll(picked);
      _conversion = suggestConversion(_conversion, _files);
    });
  }

  Future<void> _confirmAndSubmit() async {
    final a = widget.assignment;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit to Gradescope?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.course.name} — ${a.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Gradescope will receive:'),
              for (final n in outputNames(_conversion, _files)) Text('•  $n'),
              const SizedBox(height: 12),
              const Text(
                  'This replaces your current submission for this assignment.'),
              if (isPastDue(a)) ...[
                const SizedBox(height: 8),
                Text('This assignment looks closed, so Gradescope may reject it.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await Api.instance.submit(
        widget.course.id,
        a.id!, // the assignments list only opens this page when id is set
        _files,
        convertTo: switch (_conversion) {
          ConvertTo(:final target) => target,
          _ => null,
        },
        combineImagesToPdf: _conversion is CombineToPdf,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SubmittedPage(
              course: widget.course, assignment: a, result: result),
        ),
        result: true, // tells the assignments list to reload
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AssignmentContent>(
      future: _content,
      builder: (context, snap) {
        final content = snap.data;
        if (content == null || content.questions.isEmpty) return _uploadForm(context, snap);
        // An online assignment: answer its questions instead of uploading files.
        final spec = _spec ??= assignmentSpec(widget.assignment.name, content.questions,
            existingFiles: content.files);
        final answers = _answers ??= prefilledAnswers(spec, content.answers);
        final resubmit = _hasSubmission(content);
        return Scaffold(
          appBar: AppBar(
              title: Text(widget.assignment.name), actions: const [LogoutButton()]),
          body: PageWidth(
            child: AssignmentView(
              assignment: spec,
              answers: answers,
              conversionFormats: _formats,
              banner: resubmit
                  ? SubmissionBanner(
                      submission: content.submission, assignment: widget.assignment)
                  : null,
              submitLabel: resubmit ? 'Resubmit' : 'Submit',
              onSubmit: (answers) => _saveAnswers(answers, spec),
              onDone: () => Navigator.of(context).pop(true),
            ),
          ),
        );
      },
    );
  }

  Widget _uploadForm(BuildContext context, AsyncSnapshot<AssignmentContent> questions) {
    final a = widget.assignment;
    final theme = Theme.of(context);
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: Text(a.name), actions: const [LogoutButton()]),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.course.name, style: theme.textTheme.titleMedium),
            Text([
              a.dueDate == null ? 'No due date' : 'Due ${formatDate(a.dueDate!)}',
              if (a.lateDueDate != null) 'late until ${formatDate(a.lateDueDate!)}',
              if (a.status.isNotEmpty) a.status,
            ].join(' · ')),
            if (isPastDue(a))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('This assignment appears to be closed.',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            _QuestionsStatus(
              snapshot: questions,
              onRetry: _reload,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Files', style: theme.textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Add files'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_files.isEmpty)
              Card.outlined(
                child: InkWell(
                  onTap: _submitting ? null : _pickFiles,
                  child: const Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.upload_file, size: 40),
                        SizedBox(height: 8),
                        Text('Choose the files to submit'),
                      ],
                    ),
                  ),
                ),
              )
            else
              Card.outlined(
                clipBehavior: Clip.antiAlias,
                child: ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => setState(
                      () => _files.insert(to, _files.removeAt(from))),
                  children: [
                    for (final (i, f) in _files.indexed)
                      ListTile(
                        key: ObjectKey(f),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_indicator),
                        ),
                        title: Text(f.name),
                        subtitle: f.lengthSync() == null
                            ? null
                            : Text(formatSize(f.lengthSync()!)),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _files.removeAt(i)),
                        ),
                      ),
                  ],
                ),
              ),
            if (_files.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Drag to reorder — this is the page order for a combined PDF.',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 24),
            Text('Before submitting', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ConversionPicker(
              conversion: _conversion,
              files: _files,
              formats: _formats,
              onChanged: _submitting ? null : (c) => setState(() => _conversion = c),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (problem == null && !_submitting) ? _confirmAndSubmit : null,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_submitting
                    ? (_conversion is NoConversion
                        ? 'Uploading…'
                        : 'Converting and uploading…')
                    : 'Review and submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// While the questions load, or why they couldn't. Upload-only assignments
/// have none, and show nothing here.
class _QuestionsStatus extends StatelessWidget {
  const _QuestionsStatus({required this.snapshot, required this.onRetry});

  final AsyncSnapshot<AssignmentContent> snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(semanticsLabel: 'Loading questions'),
      );
    }
    final err = snapshot.error;
    if (err == null) return const SizedBox.shrink();
    if (err is ApiException && err.isUnauthorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showApiError(context, err));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: Text("Couldn't load the questions: $err",
                style: TextStyle(color: theme.colorScheme.error)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Gradescope's questions as a form to fill in.
///
/// A Gradescope question can hold several inputs (a URL box, a multiple choice,
/// a file upload); each becomes its own form question, titled by the text just
/// above it. Ids are `<question id>/<input number>`, which is how Gradescope
/// keys a question's answers.
AssignmentSpec assignmentSpec(String title, List<OnlineQuestion> questions,
    {Map<String, List<String>> existingFiles = const {}}) {
  final items = <AssignmentItem>[];
  final byId = {for (final q in questions) q.id: q};
  num total = 0;
  for (final q in questions) {
    total += double.tryParse(q.weight ?? '') ?? 0;
    final number = [
      if (byId[q.parentId] case final parent?) parent.index,
      q.index,
    ].join('.');
    final name = q.title.isEmpty ? 'Question $number' : 'Q$number  ${q.title}';
    if (questions.length > 1 && q.weight != null) {
      items.add(TextBlock(id: q.id, title: name, text: _points(q.weight!)));
    }
    final pending = <String>[];
    var input = 0;
    for (final b in q.blocks) {
      final id = '${q.id}/$input';
      // The text right above an input is its prompt; anything earlier stands alone.
      String takeTitle() {
        if (pending.length > 1) {
          items.add(TextBlock(
              id: '$id/text', text: pending.sublist(0, pending.length - 1).join('\n\n')));
        }
        final t = pending.isEmpty ? '$name, answer ${input + 1}' : pending.last;
        pending.clear();
        return t;
      }

      switch (b.type) {
        case 'text':
          if ((b.text ?? '').trim().isNotEmpty) pending.add(b.text!.trim());
          continue;
        case 'radio_input':
          items.add(MultipleChoiceQuestion(
              id: id, title: takeTitle(), options: b.choices, required: false));
        case 'free_response_input':
          items.add(FreeResponseQuestion(
              id: id, title: takeTitle(), lines: 1, required: false));
        case 'file_upload_input':
          items.add(FileUploadQuestion(
              id: id,
              title: takeTitle(),
              required: false,
              existingFiles: existingFiles[id] ?? const []));
        default:
          continue; // a kind of input this app doesn't know; leave it to Gradescope
      }
      input++;
    }
    if (pending.isNotEmpty) {
      items.add(TextBlock(id: '${q.id}/end', text: pending.join('\n\n')));
    }
  }
  return AssignmentSpec(
    title: title,
    description: total > 0 ? 'Worth ${_points(total.toString())}.' : null,
    items: items,
  );
}

/// "2.0" -> "2 pts", "1" -> "1 pt".
String _points(String weight) {
  final w = double.tryParse(weight) ?? 0;
  final n = w == w.roundToDouble() ? w.toInt().toString() : w.toString();
  return w == 1 ? '$n pt' : '$n pts';
}

/// Answers to start the form with: what was saved on Gradescope, by input id.
/// A saved choice that isn't one of the options is left unpicked.
AssignmentAnswers prefilledAnswers(AssignmentSpec spec, Map<String, String> saved) {
  final answers = AssignmentAnswers();
  for (final q in spec.questions) {
    final value = saved[q.id];
    if (value == null) continue;
    switch (q) {
      case FreeResponseQuestion():
        answers.setText(q.id, value);
      case MultipleChoiceQuestion():
        final i = q.options.indexOf(value);
        if (i >= 0) answers.toggleChoice(q, i);
      case FileUploadQuestion():
        break; // listed from the spec's existingFiles instead
    }
  }
  return answers;
}

/// "Submitted Oct 22, 1:00 PM · 1.5 / 2 pts", with a link to it on Gradescope.
class SubmissionBanner extends StatelessWidget {
  const SubmissionBanner({super.key, required this.submission, required this.assignment});

  final PastSubmission? submission;
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = submission;
    final (score, total) = s?.score != null
        ? (s!.score, s.totalPoints)
        : (assignment.grade, assignment.maxGrade);
    final url = s?.url;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.task_alt_rounded, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        s?.createdAt == null
                            ? 'Submitted'
                            : 'Submitted ${formatDate(s!.createdAt!)}',
                        if (score != null) total == null ? score : '$score / $total pts',
                      ].join(' · '),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your saved answers are filled in below. Resubmitting replaces the ones you change.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (url != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View on Gradescope'),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class SubmittedPage extends StatelessWidget {
  const SubmittedPage({
    super.key,
    required this.course,
    required this.assignment,
    required this.result,
  });

  final Course course;
  final Assignment assignment;
  final SubmitResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = Uri.parse(result.submissionUrl);
    return Scaffold(
      appBar: AppBar(title: const Text('Submitted'), actions: const [LogoutButton()]),
      body: PageWidth(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Submitted to ${assignment.name}',
                textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            Text(course.name, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text('Files sent:', style: theme.textTheme.titleSmall),
            for (final f in result.files) Text('•  $f'),
            const SizedBox(height: 24),
            SelectableText(result.submissionUrl, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => launchUrl(url, webOnlyWindowName: '_blank'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View on Gradescope'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result.submissionUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')));
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy link'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to assignments'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
