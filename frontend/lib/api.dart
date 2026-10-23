import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Backend address. Defaults to this computer: `10.0.2.2` is how the Android
/// emulator reaches it. A real phone needs the computer's Wi-Fi IP:
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8000
final backendUrl = const String.fromEnvironment('BACKEND_URL').isNotEmpty
    ? const String.fromEnvironment('BACKEND_URL')
    : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';

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

/// An online assignment's questions, plus what's already on Gradescope.
class AssignmentContent {
  AssignmentContent.fromJson(Map<String, dynamic> j)
      : questions = [
          for (final q in j['questions'] ?? const []) OnlineQuestion.fromJson(q)
        ],
        answers = {
          for (final MapEntry(:key, :value) in (j['answers'] as Map? ?? const {}).entries)
            '$key': _str(value) ?? '',
        },
        files = {
          for (final MapEntry(:key, :value) in (j['files'] as Map? ?? const {}).entries)
            '$key': [for (final name in value) _str(name) ?? ''],
        },
        submission = j['submission'] == null
            ? null
            : PastSubmission.fromJson(j['submission']);

  final List<OnlineQuestion> questions;

  /// Saved answers by `<question id>/<input number>`: typed text, or the chosen option.
  final Map<String, String> answers;

  /// Names of files already uploaded, by `<question id>/<input number>`.
  final Map<String, List<String>> files;

  /// The latest submission, when Gradescope showed one.
  final PastSubmission? submission;
}

class PastSubmission {
  PastSubmission.fromJson(Map<String, dynamic> j)
      : createdAt = _date(j['created_at']),
        score = _str(j['score']),
        totalPoints = _str(double.tryParse(_str(j['total_points']) ?? '')),
        url = _str(j['url']);

  final DateTime? createdAt;
  final String? score, totalPoints, url;
}

/// One question of an online assignment.
class OnlineQuestion {
  OnlineQuestion.fromJson(Map<String, dynamic> j)
      : id = _str(j['id']) ?? '',
        parentId = _str(j['parent_id']),
        index = _str(j['index']) ?? '',
        title = _str(j['title'])?.trim() ?? '',
        weight = _str(j['weight']),
        blocks = [
          for (final b in j['content'] ?? const []) QuestionBlock.fromJson(b)
        ];

  final String id, index, title;
  final String? parentId, weight;
  final List<QuestionBlock> blocks;
}

/// A piece of a question: some text, a multiple choice, or where an answer goes.
class QuestionBlock {
  QuestionBlock.fromJson(Map<String, dynamic> j)
      : type = _str(j['type']) ?? '',
        text = _str(j['value']),
        choices = [for (final c in j['choices'] ?? const []) _str(c['value']) ?? ''];

  /// text, radio_input, file_upload_input, free_response_input, or something newer.
  final String type;
  final String? text;
  final List<String> choices;
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
      await http
          .post(Uri.parse('$backendUrl/auth/logout'), headers: _auth)
          .timeout(const Duration(seconds: 5));
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

  /// The assignment's questions and what's been submitted; no questions for
  /// upload-only assignments.
  Future<AssignmentContent> content(String courseId, String assignmentId) async {
    final res = await _send(() => http.get(
        Uri.parse('$backendUrl/courses/$courseId/assignments/$assignmentId/content'),
        headers: _auth));
    return AssignmentContent.fromJson(res);
  }

  /// Saves answers to an online assignment. Keys are `<question id>/<input number>`.
  Future<void> saveAnswers(
    String courseId,
    String assignmentId, {
    required Map<String, String> text,
    required Map<String, String> choices, // the chosen option's text, as Gradescope stores it
    required Map<String, List<PlatformFile>> files,
    Map<String, String> conversions = const {}, // "none", "combine" or "to:<ext>"
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$backendUrl/courses/$courseId/assignments/$assignmentId/answers'),
    )
      ..headers.addAll(_auth)
      ..fields['answers'] = jsonEncode(text)
      ..fields['choices'] = jsonEncode(choices)
      ..fields['conversions'] = jsonEncode(conversions);
    for (final MapEntry(key: input, value: list) in files.entries) {
      for (final f in list) {
        req.files.add(http.MultipartFile(
          'files',
          f.readAsByteStream(),
          await f.length() ?? 0,
          filename: '$input/${f.name}', // the backend splits off which input it's for
        ));
      }
    }
    await _send(() async => http.Response.fromStream(await req.send()), timeout: null);
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
    // No time limit: big uploads and video conversion can take minutes.
    final res = await _send(() async => http.Response.fromStream(await req.send()),
        timeout: null);
    return SubmitResult(res['submission_url'], List<String>.from(res['files']));
  }

  /// Runs a request and returns the decoded JSON, or throws [ApiException].
  ///
  /// Gives up after [timeout] so a wrong address or a stuck server shows an
  /// error instead of spinning forever.
  Future<dynamic> _send(Future<http.Response> Function() request,
      {Duration? timeout = const Duration(seconds: 45)}) async {
    final http.Response res;
    try {
      res = await (timeout == null ? request() : request().timeout(timeout));
    } on TimeoutException {
      throw ApiException(0,
          "The backend at $backendUrl didn't answer. Is the server running, "
          'and is that the right address for this device?');
    } catch (_) {
      throw ApiException(0,
          "Can't reach the backend at $backendUrl. Is the server running?");
    }
    if (res.statusCode == 401) _token = null;
    final dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      // A plain-text 500, a proxy's error page, or not our backend at all.
      throw ApiException(res.statusCode,
          'Unexpected response (${res.statusCode}) from the backend at $backendUrl.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final detail = body is Map ? body['detail'] : null;
    throw ApiException(
        res.statusCode, detail is String ? detail : 'Error ${res.statusCode}');
  }
}
