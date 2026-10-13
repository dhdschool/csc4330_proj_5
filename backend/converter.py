"""File conversion: video/audio through ffmpeg, images through Pillow.

Supported targets:
  mp4  <- mov, m4v, avi, mkv, webm, 3gp, mp4
  mp3  <- m4a, wav, aac, ogg, flac, mov, mp4, webm
  pdf  <- jpg, jpeg, png, heic, heif, webp (several images become one multi-page PDF)
  jpg  <- png, heic, heif, webp, jpeg
  png  <- jpg, jpeg, heic, heif, webp
"""

import subprocess
from pathlib import Path

from PIL import Image

try:  # HEIC/HEIF (iPhone photos) support
    from pillow_heif import register_heif_opener

    register_heif_opener()
except ImportError:
    pass

FFMPEG_TIMEOUT_SECONDS = 15 * 60

VIDEO_EXT = {"mov", "m4v", "avi", "mkv", "webm", "3gp", "mp4"}
AUDIO_EXT = {"m4a", "wav", "aac", "ogg", "flac", "mp3"}
IMAGE_EXT = {"jpg", "jpeg", "png", "heic", "heif", "webp"}

SUPPORTED = {
    "mp4": VIDEO_EXT,
    "mp3": AUDIO_EXT | VIDEO_EXT,
    "pdf": IMAGE_EXT,
    "jpg": IMAGE_EXT,
    "png": IMAGE_EXT,
}


class ConversionError(Exception):
    pass


def ext_of(path: Path) -> str:
    return path.suffix.lower().lstrip(".")


def can_convert(src_ext: str, target: str) -> bool:
    return target in SUPPORTED and src_ext in SUPPORTED[target]


def convert(src: Path, target: str, out_dir: Path) -> Path:
    """Convert one file. Returns the path of the converted file."""
    target = target.lower()
    src_ext = ext_of(src)
    if src_ext == target:
        return src
    if not can_convert(src_ext, target):
        raise ConversionError(f"Can't convert .{src_ext} to .{target}")

    out = out_dir / f"{src.stem}.{target}"
    if target == "mp4":
        _ffmpeg([
            "-i", str(src),
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
            "-pix_fmt", "yuv420p",          # plays everywhere, including browsers
            "-c:a", "aac", "-b:a", "160k",
            "-movflags", "+faststart",      # lets the video start before fully loaded
            str(out),
        ])
    elif target == "mp3":
        _ffmpeg(["-i", str(src), "-vn", "-c:a", "libmp3lame", "-q:a", "2", str(out)])
    elif target == "pdf":
        images_to_pdf([src], out)
    else:  # jpg / png
        with Image.open(src) as img:
            img = img.convert("RGB") if target == "jpg" else img
            img.save(out, "JPEG" if target == "jpg" else "PNG", quality=92)
    return out


def images_to_pdf(images: list[Path], out: Path) -> Path:
    """Combine images (in order) into one PDF, one image per page."""
    if not images:
        raise ConversionError("No images given")
    pages = []
    try:
        for p in images:
            if ext_of(p) not in IMAGE_EXT:
                raise ConversionError(f"{p.name} is not an image")
            pages.append(Image.open(p).convert("RGB"))
        pages[0].save(out, "PDF", save_all=True, append_images=pages[1:], resolution=150)
    finally:
        for page in pages:
            page.close()
    return out


def _ffmpeg(args: list[str]) -> None:
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=FFMPEG_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        raise ConversionError("Conversion took too long")
    except FileNotFoundError:
        raise ConversionError("ffmpeg is not installed on the server")
    if result.returncode != 0:
        raise ConversionError(f"ffmpeg failed: {result.stderr.strip()[-500:]}")
