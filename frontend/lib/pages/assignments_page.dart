import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/ui.dart';
import 'common.dart';
import 'courses_page.dart' show CourseBadge;
import 'submit_page.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key, required this.course});

  final Course course;

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  late Future<List<Assignment>> _future = _load();

  Future<List<Assignment>> _load() async {
    final items = await Api.instance.assignments(widget.course.id);
    // Upcoming first (soonest due), then past ones (most recent first).
    final now = DateTime.now();
    int rank(Assignment a) =>
        a.dueDate == null ? 1 : (a.dueDate!.isAfter(now) ? 0 : 2);
    items.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0 || a.dueDate == null || b.dueDate == null) return r;
      return rank(a) == 0
          ? a.dueDate!.compareTo(b.dueDate!)
          : b.dueDate!.compareTo(a.dueDate!);
    });
    return items;
  }

  Future<void> _open(Assignment a) async {
    final submitted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SubmitPage(course: widget.course, assignment: a)));
    // Otherwise "Back to assignments" still shows the old status.
    if (submitted == true && mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        actions: const [LogoutButton()],
      ),
      body: PageWidth(
        child: AsyncList<Assignment>(
          future: _future,
          onRetry: () => setState(() => _future = _load()),
          emptyText: 'No assignments in this course.',
          emptyIcon: Icons.assignment_outlined,
          builder: (context, items) {
            final now = DateTime.now();
            final groups = [
              ('Upcoming', items.where((a) => a.dueDate?.isAfter(now) ?? false)),
              ('No due date', items.where((a) => a.dueDate == null)),
              ('Past', items.where((a) => !(a.dueDate?.isAfter(now) ?? true))),
            ];
            return [
              _CourseSummary(course: widget.course, items: items),
              for (final (label, group) in groups)
                if (group.isNotEmpty) ...[
                  _SectionLabel(label: label, count: group.length),
                  for (final a in group)
                    AssignmentCard(
                      assignment: a,
                      onTap: a.canSubmit ? () => _open(a) : null,
                    ),
                ],
            ];
          },
        ),
      ),
    );
  }
}

class _CourseSummary extends StatelessWidget {
  const _CourseSummary({required this.course, required this.items});

  final Course course;
  final List<Assignment> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final upcoming = items.where((a) => a.dueDate?.isAfter(now) ?? false).length;
    final submitted = items.where(isSubmitted).length;
    final graded = items.where((a) => a.grade != null && a.maxGrade != null).length;
    final term = '${course.semester} ${course.year}'.trim();
    final subtitle = [
      if (course.fullName.isNotEmpty && course.fullName != course.name) course.fullName,
      if (term.isNotEmpty) term,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CourseBadge(course: course, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(icon: Icons.event_rounded, label: '$upcoming upcoming'),
                    Pill(icon: Icons.task_alt_rounded, label: '$submitted submitted'),
                    if (graded > 0)
                      Pill(icon: Icons.grade_outlined, label: '$graded graded'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
          const SizedBox(width: 8),
          Text('$count',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment, this.onTap});

  final Assignment assignment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = assignment;
    final now = DateTime.now();
    final closed = isPastDue(a);
    final submitted = isSubmitted(a);
    final graded = a.grade != null && a.maxGrade != null;
    final urgent = !submitted &&
        a.dueDate != null &&
        a.dueDate!.isAfter(now) &&
        a.dueDate!.difference(now).inHours < 24;

    final (icon, bg, fg) = submitted
        ? (Icons.check_rounded, scheme.primary, scheme.onPrimary)
        : !a.canSubmit
            ? (Icons.block_rounded, scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
            : closed
                ? (Icons.lock_clock_outlined, scheme.surfaceContainerHighest,
                    scheme.onSurfaceVariant)
                : urgent
                    ? (Icons.alarm_rounded, scheme.errorContainer, scheme.onErrorContainer)
                    : (Icons.edit_note_rounded, scheme.secondaryContainer,
                        scheme.onSecondaryContainer);

    final details = [
      a.dueDate == null ? 'No due date' : 'Due ${formatDate(a.dueDate!)}',
      if (a.status.isNotEmpty) a.status,
      if (!a.canSubmit) "Can't submit here",
    ].join(' · ');
    final due = _duePill(a, scheme, now);

    return Opacity(
      opacity: a.canSubmit || submitted ? 1 : 0.6,
      child: PressableCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: fg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (due != null) ...[
                    const SizedBox(height: 8),
                    due,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (graded)
              _GradeRing(grade: a.grade!, maxGrade: a.maxGrade!)
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// Time left, colored by how soon it is; or the late window if that's open.
  static Widget? _duePill(Assignment a, ColorScheme scheme, DateTime now) {
    final due = a.dueDate;
    if (due == null || isSubmitted(a)) return null;
    if (due.isAfter(now)) {
      final left = due.difference(now);
      final (bg, fg) = left.inHours < 24
          ? (scheme.errorContainer, scheme.onErrorContainer)
          : left.inDays < 3
              ? (scheme.tertiaryContainer, scheme.onTertiaryContainer)
              : (scheme.secondaryContainer, scheme.onSecondaryContainer);
      return Pill(icon: Icons.schedule_rounded, label: timeLeft(left), color: bg, onColor: fg);
    }
    final late = a.lateDueDate;
    if (late != null && late.isAfter(now)) {
      return Pill(
        icon: Icons.hourglass_bottom_rounded,
        label: 'Late until ${formatDate(late)}',
        color: scheme.tertiaryContainer,
        onColor: scheme.onTertiaryContainer,
      );
    }
    return null;
  }
}

/// Score ring that fills up to the grade.
class _GradeRing extends StatelessWidget {
  const _GradeRing({required this.grade, required this.maxGrade});

  final String grade, maxGrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = double.tryParse(grade);
    final m = double.tryParse(maxGrade);
    final fraction = g != null && m != null && m > 0 ? (g / m).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      container: true,
      label: 'Grade $grade out of $maxGrade',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => SizedBox.expand(
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(grade,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('/ $maxGrade',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
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

/// Past the late due date (or the due date, if there's no late one).
bool isPastDue(Assignment a) {
  final last = a.lateDueDate ?? a.dueDate;
  return last != null && last.isBefore(DateTime.now());
}

bool isSubmitted(Assignment a) =>
    a.status.isNotEmpty && !a.status.toLowerCase().contains('no submission');

/// "45 min left", "5 h left", "3 days left".
String timeLeft(Duration d) {
  if (d.inMinutes < 60) return '${math.max(1, d.inMinutes)} min left';
  if (d.inHours < 24) return '${d.inHours} h left';
  return d.inDays == 1 ? '1 day left' : '${d.inDays} days left';
}

String formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${months[d.month - 1]} ${d.day}, $hour:$minute $ampm';
}
