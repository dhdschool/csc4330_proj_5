import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// What to do with the files before they go to Gradescope.
sealed class Conversion {
  const Conversion();

  /// How the dropdown (and the backend's answers endpoint) names it.
  String get key => switch (this) {
        NoConversion() => 'none',
        CombineToPdf() => 'combine',
        ConvertTo(:final target) => 'to:$target',
      };
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

String fileExt(PlatformFile f) =>
    (f.extension ?? '').toLowerCase().replaceFirst('.', '');

/// Why [conversion] won't work for [files], or null if it will.
///
/// [formats] is target format -> source extensions; when it hasn't loaded we
/// skip the check and leave it to the backend.
String? conversionProblem(Conversion conversion, List<PlatformFile> files,
    Map<String, List<String>> formats) {
  switch (conversion) {
    case NoConversion():
      return null;
    case CombineToPdf():
      final images = formats['pdf'];
      final bad = images == null
          ? <PlatformFile>[]
          : files.where((f) => !images.contains(fileExt(f))).toList();
      return bad.isEmpty
          ? null
          : 'Only images can be combined into a PDF: ${bad.map((f) => f.name).join(', ')}';
    case ConvertTo(:final target):
      final sources = formats[target];
      if (sources == null) return null;
      final bad = files
          .where((f) => fileExt(f) != target && !sources.contains(fileExt(f)))
          .toList();
      return bad.isEmpty
          ? null
          : "Can't convert to .$target: ${bad.map((f) => f.name).join(', ')}";
  }
}

/// Phone photos -> one PDF, phone videos -> mp4, otherwise leave alone.
/// Never overrides a choice the student already made.
Conversion suggestConversion(Conversion current, List<PlatformFile> files) {
  if (current is! NoConversion) return current;
  final exts = files.map(fileExt).toSet();
  const photoExts = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'};
  const phoneVideoExts = {'mov', 'm4v', '3gp'};
  if (files.length > 1 && exts.every(photoExts.contains)) {
    return const CombineToPdf();
  }
  if (exts.any({'heic', 'heif'}.contains) && exts.every(photoExts.contains)) {
    return const ConvertTo('pdf');
  }
  if (exts.any(phoneVideoExts.contains) &&
      exts.every({...phoneVideoExts, 'mp4'}.contains)) {
    return const ConvertTo('mp4');
  }
  return current;
}

/// File names Gradescope will receive, matching what the backend does.
List<String> outputNames(Conversion conversion, List<PlatformFile> files) {
  switch (conversion) {
    case NoConversion():
      return files.map((f) => f.name).toList();
    case CombineToPdf():
      return ['submission.pdf'];
    case ConvertTo(:final target):
      return files.map((f) {
        if (fileExt(f) == target) return f.name;
        final dot = f.name.lastIndexOf('.');
        return '${dot > 0 ? f.name.substring(0, dot) : f.name}.$target';
      }).toList();
  }
}

/// Dropdown for what to do with [files] before submitting, plus what
/// Gradescope will receive and anything that won't work.
class ConversionPicker extends StatelessWidget {
  const ConversionPicker({
    super.key,
    required this.conversion,
    required this.files,
    required this.formats,
    required this.onChanged,
    this.label,
  });

  final Conversion conversion;
  final List<PlatformFile> files;
  final Map<String, List<String>> formats;

  /// Null disables the dropdown (e.g. while submitting).
  final ValueChanged<Conversion>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = conversionProblem(conversion, files, formats);
    final targets = {
      ...formats.keys,
      // A conversion suggested before the format list loaded (or if it failed)
      // still needs its menu item, or the dropdown throws.
      if (conversion case ConvertTo(:final target)) target,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: conversion.key,
          key: ValueKey(conversion.key),
          isExpanded: true, // long labels shrink to fit a phone instead of overflowing
          decoration: InputDecoration(
              border: const OutlineInputBorder(), labelText: label),
          items: [
            const DropdownMenuItem(
                value: 'none', child: Text('Submit files as they are')),
            const DropdownMenuItem(
                value: 'combine', child: Text('Combine images into one PDF')),
            for (final t in targets)
              DropdownMenuItem(value: 'to:$t', child: Text('Convert each file to .$t')),
          ],
          onChanged: onChanged == null
              ? null
              : (v) => onChanged!(switch (v) {
                    'combine' => const CombineToPdf(),
                    final String s when s.startsWith('to:') => ConvertTo(s.substring(3)),
                    _ => const NoConversion(),
                  }),
        ),
        if (files.isNotEmpty && conversion is! NoConversion) ...[
          const SizedBox(height: 8),
          Text('Gradescope will receive: ${outputNames(conversion, files).join(', ')}',
              style: theme.textTheme.bodySmall),
        ],
        if (problem != null && files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(problem, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
