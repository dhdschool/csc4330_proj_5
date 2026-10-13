import 'package:flutter/material.dart';

import '../api.dart';
import 'common.dart';
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
          itemBuilder: (context, a) {
            final pastDue = isPastDue(a);
            return ListTile(
              leading: Icon(
                a.status.toLowerCase().contains('no submission')
                    ? Icons.assignment_outlined
                    : Icons.assignment_turned_in_outlined,
              ),
              title: Text(a.name),
              subtitle: Text([
                a.dueDate == null ? 'No due date' : 'Due ${formatDate(a.dueDate!)}',
                if (a.status.isNotEmpty) a.status,
                if (a.grade != null && a.maxGrade != null)
                  '${a.grade} / ${a.maxGrade}',
              ].join(' · ')),
              enabled: a.canSubmit,
              trailing: (pastDue || !a.canSubmit)
                  ? Text(a.canSubmit ? 'Closed' : "Can't submit",
                      style: TextStyle(color: Theme.of(context).disabledColor))
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      SubmitPage(course: widget.course, assignment: a))),
            );
          },
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
