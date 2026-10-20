import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/ui.dart';
import 'assignments_page.dart';
import 'common.dart';

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  late Future<List<Course>> _future = _load();

  Future<List<Course>> _load() async {
    final courses = await Api.instance.courses();
    // Student courses first, newest year first.
    courses.sort((a, b) {
      if (a.role != b.role) return a.role == 'student' ? -1 : 1;
      return b.year.compareTo(a.year);
    });
    return courses;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your courses'),
        actions: const [LogoutButton()],
      ),
      body: PageWidth(
        child: AsyncList<Course>(
          future: _future,
          onRetry: () => setState(() => _future = _load()),
          emptyText: 'No courses found on your Gradescope account.',
          emptyIcon: Icons.school_outlined,
          builder: (context, courses) => [
            for (final c in courses)
              CourseCard(
                course: c,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AssignmentsPage(course: c))),
              ),
          ],
        ),
      ),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course, this.onTap});

  final Course course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = course;
    final term = '${c.semester} ${c.year}'.trim();
    final instructor = c.role == 'instructor';
    return PressableCard(
      onTap: onTap,
      child: Row(
        children: [
          CourseBadge(course: c),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (c.fullName.isNotEmpty && c.fullName != c.name)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(c.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                if (term.isNotEmpty || instructor)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (term.isNotEmpty)
                          Pill(icon: Icons.calendar_today_rounded, label: term),
                        if (instructor)
                          Pill(
                            icon: Icons.co_present_outlined,
                            label: 'Instructor',
                            color: scheme.tertiaryContainer,
                            onColor: scheme.onTertiaryContainer,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Course code on a gradient square. Each course gets its own color,
/// picked from its id so it stays the same between visits.
class CourseBadge extends StatelessWidget {
  const CourseBadge({super.key, required this.course, this.size = 48});

  final Course course;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hash =
        course.id.codeUnits.fold<int>(0, (h, u) => (h * 31 + u) & 0x7fffffff);
    final hue = (hash % 360).toDouble();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.6, 0.45).toColor(),
            HSLColor.fromAHSL(1, (hue + 35) % 360, 0.6, 0.36).toColor(),
          ],
        ),
      ),
      child: FittedBox(
        child: Text(courseInitials(course.name),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
    );
  }
}

/// "CSC 4330" -> "CSC", "Intro to Programming" -> "IT".
String courseInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.first.length <= 4 && RegExp(r'^[A-Za-z]+$').hasMatch(words.first)) {
    return words.first.toUpperCase();
  }
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}
