import 'package:flutter/material.dart';

import '../api.dart';
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
          itemBuilder: (context, c) => ListTile(
            leading: const Icon(Icons.class_outlined),
            title: Text(c.name),
            subtitle: Text([
              if (c.fullName.isNotEmpty && c.fullName != c.name) c.fullName,
              '${c.semester} ${c.year}'.trim(),
              if (c.role == 'instructor') 'Instructor',
            ].where((s) => s.isNotEmpty).join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AssignmentsPage(course: c))),
          ),
        ),
      ),
    );
  }
}
