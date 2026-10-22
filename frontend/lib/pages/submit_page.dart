import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import 'assignments_page.dart' show formatDate, isPastDue;
import 'common.dart';

/// What to do with the files before they go to Gradescope.
sealed class Conversion {
  const Conversion();
}

class NoConversion extends Conversion {
  const NoConversion();
}

class ConvertTo extends Conversion {
  const ConvertTo(this.target);
  final String target;
}

class CombineToPdf extends Conversion {
  const CombineToPdf();
}

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

  @override
  void initState() {
    super.initState();
    Api.instance.formats().then((f) {
      if (mounted) setState(() => _formats = f);
    }).catchError((_) {
      // Without the list we just skip the local check; the backend still validates.
    });
  }

  String _ext(PlatformFile f) =>
      (f.extension ?? '').toLowerCase().replaceFirst('.', '');

  /// Why the current files + conversion won't work, or null if they will.
  String? get _problem {
    if (_files.isEmpty) return 'Add at least one file.';
    switch (_conversion) {
      case NoConversion():
        return null;
      case CombineToPdf():
        final images = _formats['pdf'];
        final bad = images == null
            ? <PlatformFile>[]
            : _files.where((f) => !images.contains(_ext(f))).toList();
        return bad.isEmpty
            ? null
            : 'Only images can be combined into a PDF: ${bad.map((f) => f.name).join(', ')}';
      case ConvertTo(:final target):
        final sources = _formats[target];
        if (sources == null) return null;
        final bad = _files
            .where((f) => _ext(f) != target && !sources.contains(_ext(f)))
            .toList();
        return bad.isEmpty
            ? null
            : "Can't convert to .$target: ${bad.map((f) => f.name).join(', ')}";
    }
  }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose files');
    if (picked.isEmpty) return;
    setState(() {
      _files.addAll(picked);
      _conversion = _suggestConversion();
    });
  }

  /// Phone photos -> one PDF, phone videos -> mp4, otherwise leave alone.
  Conversion _suggestConversion() {
    if (_conversion is! NoConversion) return _conversion;
    final exts = _files.map(_ext).toSet();
    const photoExts = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'};
    const phoneVideoExts = {'mov', 'm4v', '3gp'};
    if (_files.length > 1 && exts.every(photoExts.contains)) {
      return const CombineToPdf();
    }
    if (exts.any({'heic', 'heif'}.contains) && exts.every(photoExts.contains)) {
      return const ConvertTo('pdf');
    }
    if (exts.any(phoneVideoExts.contains) &&
        exts.every({...phoneVideoExts, 'mp4'}.contains)) {
      return const ConvertTo('mp4');
    }
    return _conversion;
  }

  /// File names Gradescope will receive, matching what the backend does.
  List<String> get _outputNames {
    switch (_conversion) {
      case NoConversion():
        return _files.map((f) => f.name).toList();
      case CombineToPdf():
        return ['submission.pdf'];
      case ConvertTo(:final target):
        return _files.map((f) {
          if (_ext(f) == target) return f.name;
          final dot = f.name.lastIndexOf('.');
          return '${dot > 0 ? f.name.substring(0, dot) : f.name}.$target';
        }).toList();
    }
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
              for (final n in _outputNames) Text('•  $n'),
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
    final a = widget.assignment;
    final theme = Theme.of(context);
    final problem = _problem;
    final targets = {
      ..._formats.keys,
      // A conversion suggested before the format list loaded (or if it failed)
      // still needs its menu item, or the dropdown throws.
      if (_conversion case ConvertTo(:final target)) target,
    }.toList()
      ..sort();

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
            DropdownButtonFormField<String>(
              initialValue: _conversionKey(_conversion),
              key: ValueKey(_conversionKey(_conversion)),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: 'none', child: Text('Submit files as they are')),
                const DropdownMenuItem(
                    value: 'combine',
                    child: Text('Combine images into one PDF')),
                for (final t in targets)
                  DropdownMenuItem(
                      value: 'to:$t', child: Text('Convert each file to .$t')),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _conversion = switch (v) {
                        'combine' => const CombineToPdf(),
                        final String s when s.startsWith('to:') =>
                          ConvertTo(s.substring(3)),
                        _ => const NoConversion(),
                      }),
            ),
            if (_files.isNotEmpty && _conversion is! NoConversion) ...[
              const SizedBox(height: 8),
              Text('Gradescope will receive: ${_outputNames.join(', ')}',
                  style: theme.textTheme.bodySmall),
            ],
            if (problem != null && _files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(problem, style: TextStyle(color: theme.colorScheme.error)),
            ],
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

  String _conversionKey(Conversion c) => switch (c) {
        NoConversion() => 'none',
        CombineToPdf() => 'combine',
        ConvertTo(:final target) => 'to:$target',
      };
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
