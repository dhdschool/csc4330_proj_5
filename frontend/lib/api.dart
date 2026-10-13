import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

/// Backend address. Override with:
///   flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000   (Android emulator)
const backendUrl =
    String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');

/// An error from the backend, carrying its `detail` message.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// JSON value as a string, whatever its type (the library mixes strings and numbers).
String? _str(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    // 8.0 -> "8", 8.5 -> "8.5"
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }
  return v.toString();
}

DateTime? _date(dynamic v) => DateTime.tryParse(_str(v) ?? '')?.toLocal();

class Course {
  Course.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']) ?? '',
        role = _str(j['role']) ?? '',
        name = _str(j['name']) ?? '',
        fullName = _str(j['full_name']) ?? '',
        semester = _str(j['semester']) ?? '',
        year = _str(j['year']) ?? '';

  final String id, role, name, fullName, semester, year;
}

class Assignment {
  Assignment.fromJson(Map<String, dynamic> j)
      : id = _str(j['assignment_id']),
        name = _str(j['name'])?.trim() ?? '',
        dueDate = _date(j['due_date']),
        lateDueDate = _date(j['late_due_date']),
        status = _str(j['submissions_status'])?.trim() ?? '',
        grade = _str(j['grade']),
        maxGrade = _str(j['max_grade']);

  /// Null when Gradescope doesn't offer a submit button for it.
  final String? id;
  final String name, status;
  final DateTime? dueDate, lateDueDate;
  final String? grade, maxGrade;

  bool get canSubmit => id != null;
}

class SubmitResult {
  SubmitResult(this.submissionUrl, this.files);

  final String submissionUrl;
  final List<String> files;
}

/// Talks to our FastAPI backend (see backend/README.md).
///
/// The token only lives in memory: refreshing the page means logging in again.
/// The Gradescope password is never stored.
class Api {
  Api._();

  static final instance = Api._();

  String? _token;

  bool get isLoggedIn => _token != null;

  Map<String, String> get _auth => {'Authorization': 'Bearer $_token'};

  Future<void> login(String email, String password) async {
    final res = await _send(() => http.post(
          Uri.parse('$backendUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        ));
    _token = res['token'];
  }

  Future<void> logout() async {
    if (_token == null) return;
    try {
      await http.post(Uri.parse('$backendUrl/auth/logout'), headers: _auth);
    } catch (_) {
      // Logging out locally is enough if the backend is unreachable.
    }
    _token = null;
  }

  Future<List<Course>> courses() async {
    final res = await _send(
        () => http.get(Uri.parse('$backendUrl/courses'), headers: _auth));
    return [for (final c in res) Course.fromJson(c)];
  }

  Future<List<Assignment>> assignments(String courseId) async {
    final res = await _send(() => http.get(
        Uri.parse('$backendUrl/courses/$courseId/assignments'),
        headers: _auth));
    return [for (final a in res) Assignment.fromJson(a)];
  }

  /// Target format -> source extensions it can be made from.
  Future<Map<String, List<String>>> formats() async {
    final res = await _send(
        () => http.get(Uri.parse('$backendUrl/convert/formats')));
    return {
      for (final e in (res as Map<String, dynamic>).entries)
        e.key: List<String>.from(e.value),
    };
  }

  Future<SubmitResult> submit(
    String courseId,
    String assignmentId,
    List<PlatformFile> files, {
    String? convertTo,
    bool combineImagesToPdf = false,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$backendUrl/courses/$courseId/assignments/$assignmentId/submit'),
    )..headers.addAll(_auth);
    if (convertTo != null) req.fields['convert_to'] = convertTo;
    if (combineImagesToPdf) req.fields['combine_images_to_pdf'] = 'true';
    for (final f in files) {
      // Works on web and mobile alike: stream the bytes instead of using a path.
      req.files.add(http.MultipartFile(
        'files',
        f.readAsByteStream(),
        await f.length() ?? 0,
        filename: f.name,
      ));
    }
    final res = await _send(() async => http.Response.fromStream(await req.send()));
    return SubmitResult(res['submission_url'], List<String>.from(res['files']));
  }

  /// Runs a request and returns the decoded JSON, or throws [ApiException].
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request();
    } catch (_) {
      throw ApiException(0,
          "Can't reach the backend at $backendUrl. Is the server running?");
    }
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    if (res.statusCode == 401) _token = null;
    final detail = body is Map ? body['detail'] : null;
    throw ApiException(
        res.statusCode, detail is String ? detail : 'Error ${res.statusCode}');
  }
}
