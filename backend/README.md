# Backend

Python (FastAPI) server between the Flutter app and Gradescope. It uses the
a modified version of the unofficial [`gradescopeapi`](https://github.com/nyuoss/gradescope-api) library
for Gradescope and ffmpeg / Pillow for file conversion.

The modified version of the library is contained in ./lib/gradescope-api. 
These patches are necessary to ensure cohesion with certain added features without making too many 
identical requests to gradescope.

We don't use the library's bundled API server because it shares one Gradescope
login across every user and its upload endpoint is marked nonfunctional.

## Setup

```bash
# ffmpeg is required for video/audio conversion
#   macOS:   brew install ffmpeg
#   Ubuntu:  sudo apt install ffmpeg
#   Windows: winget install ffmpeg

cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Interactive docs: http://localhost:8000/docs

Keep it to **one worker** (`--workers 1`): logins are stored in memory.

## Endpoints

All endpoints except `/auth/login` and `/convert/formats` need
`Authorization: Bearer <token>`.

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/auth/login` | JSON `{email, password}` | `{token}` |
| POST | `/auth/logout` | – | `{ok}` |
| GET | `/courses` | – | list of courses (`id`, `role`, `name`, `full_name`, `semester`, `year`, …) |
| GET | `/courses/{course_id}/assignments` | – | list of assignments (`assignment_id`, `name`, `due_date`, `submissions_status`, …) |
| GET | `/convert/formats` | – | which source types can become which target |
| POST | `/convert` | multipart: `file`, `target` | the converted file (for previewing) |
| POST | `/courses/{course_id}/assignments/{assignment_id}/submit` | multipart: `files` (1+), optional `convert_to`, `combine_images_to_pdf`, `leaderboard_name` | `{submission_url, files}` |

Conversions: `mov/m4v/avi/mkv/webm/3gp → mp4`, video/audio `→ mp3`,
images (incl. iPhone HEIC) `→ pdf/jpg/png`. With `combine_images_to_pdf=true`,
all uploaded images become one PDF in the order they were sent (for
"upload a PDF" assignments with photos of handwritten work).

Errors come back as `{"detail": "..."}` with 401 (not logged in / wrong
password), 400 (bad conversion or Gradescope rejected the submission),
413 (file too big), or 502 (Gradescope unreachable or changed).

## Config (environment variables)

- `MAX_UPLOAD_MB` – per-file limit, default 500
- `ALLOWED_ORIGINS` – comma-separated CORS origins for the Flutter web build, default `*`

## Calling it from Flutter

With the `http` package:

```dart
final res = await http.post(Uri.parse('$base/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': password}));
final token = jsonDecode(res.body)['token'];

final req = http.MultipartRequest('POST',
    Uri.parse('$base/courses/$courseId/assignments/$assignmentId/submit'))
  ..headers['Authorization'] = 'Bearer $token'
  ..fields['convert_to'] = 'mp4'
  ..files.add(await http.MultipartFile.fromPath('files', path)); // web: fromBytes
final streamed = await req.send();
```

On an Android emulator the host machine is `http://10.0.2.2:8000`, not `localhost`.

## Known limits

- Login is Gradescope email + password only. School-SSO accounts need to set a
  Gradescope password first ("Forgot password" on gradescope.com).
- The library scrapes Gradescope's website, so it can break when Gradescope
  changes. Errors from that show up as 502.
- Test uploads on a practice assignment first; a submit replaces the current
  submission on Gradescope.
