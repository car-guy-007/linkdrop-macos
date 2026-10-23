#!/usr/bin/env python3
"""Local LinkDrop bridge for the iPhone PWA.

Listens on loopback only. Put it behind Tailscale Serve (HTTPS) for remote access.
Uses the yt-dlp/FFmpeg binaries already bundled with LinkDrop.app when available.
"""
from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP_NAME = "LinkDrop"
PORT = 8765
ALLOWED_ORIGIN = "https://car-guy-007.github.io"
BASE = Path.home() / "Library" / "Application Support" / APP_NAME
TOKEN_FILE = BASE / "remote-token"
DOWNLOAD_DIR = Path.home() / "Downloads"
MAX_BODY = 16_384
MAX_JOBS = 3
JOBS: dict[str, dict] = {}
LOCK = threading.Lock()
URL_RE = re.compile(r"^https?://", re.I)
BLOCKED_HOSTS = {"localhost", "localhost.localdomain"}


def tools():
    candidates = [
        Path("/Applications/LinkDrop.app/Contents/Resources/tools"),
        Path.home() / "Applications/LinkDrop.app/Contents/Resources/tools",
    ]
    arch = "arm64" if __import__("platform").machine() == "arm64" else "amd64"
    ytdlp = shutil.which("yt-dlp")
    ffmpeg = shutil.which("ffmpeg")
    for root in candidates:
        if root.exists():
            y = root / "yt-dlp_macos"
            f = root / arch / "ffmpeg"
            if y.is_file() and os.access(y, os.X_OK):
                ytdlp = str(y)
            if f.is_file() and os.access(f, os.X_OK):
                ffmpeg = str(f)
            break
    if not ytdlp:
        raise RuntimeError("yt-dlp not found. Install LinkDrop.app in /Applications first.")
    return ytdlp, ffmpeg


def get_token():
    BASE.mkdir(parents=True, exist_ok=True)
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text().strip()
        if len(token) >= 40:
            return token
    token = secrets.token_urlsafe(36)
    TOKEN_FILE.write_text(token + "\n")
    TOKEN_FILE.chmod(0o600)
    return token


def valid_public_url(raw):
    if not isinstance(raw, str) or len(raw) > 4096 or not URL_RE.match(raw):
        return False
    try:
        p = urllib.parse.urlsplit(raw)
        host = (p.hostname or "").lower().rstrip(".")
        if not host or p.username or p.password or host in BLOCKED_HOSTS:
            return False
        # Refuse literal private/local IP targets. Site extractors may redirect, so this is
        # a guardrail rather than a complete SSRF defense.
        import ipaddress
        try:
            ip = ipaddress.ip_address(host)
            if not ip.is_global:
                return False
        except ValueError:
            if "." not in host:
                return False
        return p.scheme in ("http", "https")
    except Exception:
        return False


def run_download(job_id, url, quality, playlist):
    try:
        ytdlp, ffmpeg = tools()
        outtmpl = str(DOWNLOAD_DIR / "%(title).160B [%(id)s].%(ext)s")
        args = [ytdlp, "--ignore-config", "--no-colors", "--newline", "--continue",
                "--no-overwrites", "--no-playlist" if not playlist else "--yes-playlist",
                "--socket-timeout", "25", "--retries", "5", "--fragment-retries", "5",
                "--restrict-filenames", "-o", outtmpl,
                "--print", "after_move:LINKDROP_FILE:%(filepath)s"]
        if ffmpeg:
            args += ["--ffmpeg-location", str(Path(ffmpeg).parent)]
        if quality == "720":
            args += ["-f", "bv*[height<=720]+ba/b[height<=720]/b", "--merge-output-format", "mp4/mkv"]
        elif quality == "1080":
            args += ["-f", "bv*[height<=1080]+ba/b[height<=1080]/b", "--merge-output-format", "mp4/mkv"]
        elif quality == "audio":
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        else:
            args += ["-f", "bv*+ba/b", "--merge-output-format", "mp4/mkv"]
        args += ["--", url]
        with LOCK:
            JOBS[job_id].update(state="downloading", progress=0, status="Starting download", started=time.time())
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                bufsize=1, env={**os.environ, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"})
        with LOCK:
            JOBS[job_id]["process"] = proc
        for raw in proc.stdout:
            line = raw.strip()
            with LOCK:
                job = JOBS.get(job_id)
                if not job:
                    continue
                match = re.search(r"\[download\]\s+(\d+(?:\.\d+)?)%", line)
                if match:
                    job["progress"] = min(100, float(match.group(1)))
                    job["status"] = f"Downloading · {job['progress']:.1f}%"
                if line.startswith("LINKDROP_FILE:"):
                    candidate = Path(line[len("LINKDROP_FILE:"):]).expanduser().resolve()
                    try:
                        candidate.relative_to(DOWNLOAD_DIR.resolve())
                        if candidate.is_file():
                            job["file"] = str(candidate)
                    except (ValueError, OSError):
                        pass
                if "Merging formats" in line or "[ExtractAudio]" in line:
                    job["status"] = "Finishing media file…"
                job["log"] = (job.get("log", "") + line[-1000:] + "\n")[-6000:]
        code = proc.wait()
        with LOCK:
            job = JOBS[job_id]
            job.pop("process", None)
            job["finished"] = time.time()
            if code == 0 and job.get("file") and Path(job["file"]).is_file():
                job.update(state="done", progress=100, status="Finished")
            elif code == 0:
                job.update(state="done", progress=100, status="Finished; check Downloads folder")
            else:
                detail = job.get("log", "").lower()
                message = "Download failed. Check the log."
                if "drm" in detail:
                    message = "DRM-protected content is not supported."
                elif "unsupported url" in detail:
                    message = "This site or link is not supported by the current engine."
                elif "429" in detail or "too many requests" in detail:
                    message = "The site is rate-limiting requests. Try again later."
                job.update(state="error", status=message)
    except Exception as exc:
        with LOCK:
            if job_id in JOBS:
                JOBS[job_id].update(state="error", status=str(exc)[:300], finished=time.time())


class Handler(BaseHTTPRequestHandler):
    server_version = "LinkDropBridge/1.0"

    def log_message(self, fmt, *args):
        # Avoid logging full URLs, which may contain sensitive query parameters.
        print("LinkDrop bridge:", fmt % args)

    def send_json(self, status, obj):
        payload = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", ALLOWED_ORIGIN)
        self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", ALLOWED_ORIGIN)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def authorized(self):
        origin = self.headers.get("Origin", "")
        if origin and origin != ALLOWED_ORIGIN:
            self.send_json(403, {"error": "Origin not allowed"})
            return False
        supplied = self.headers.get("Authorization", "")
        if not secrets.compare_digest(supplied, "Bearer " + get_token()):
            self.send_json(401, {"error": "Pair this iPhone using the Mac's LinkDrop token"})
            return False
        return True

    def read_body(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 1 or size > MAX_BODY:
                return None
            return json.loads(self.rfile.read(size))
        except Exception:
            return None

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/health":
            self.send_json(200, {"ok": True, "app": "LinkDrop Bridge"})
            return
        if not self.authorized():
            return
        if parsed.path == "/api/jobs":
            with LOCK:
                jobs = [{k: v for k, v in job.items() if k not in ("process", "log", "url")}
                        for job in JOBS.values()]
            self.send_json(200, {"jobs": jobs})
            return
        match = re.fullmatch(r"/api/jobs/([a-f0-9]{16})", parsed.path)
        if match:
            with LOCK:
                job = JOBS.get(match.group(1))
                if not job:
                    self.send_json(404, {"error": "Job not found"})
                    return
                clean = {k: v for k, v in job.items() if k not in ("process", "url")}
            self.send_json(200, clean)
            return
        match = re.fullmatch(r"/api/jobs/([a-f0-9]{16})/file", parsed.path)
        if match:
            with LOCK:
                job = JOBS.get(match.group(1), {})
                file_path = job.get("file") if job.get("state") == "done" else None
            if not file_path or not Path(file_path).is_file():
                self.send_json(404, {"error": "Completed file not available"})
                return
            path = Path(file_path)
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(path.stat().st_size))
            self.send_header("Content-Disposition", "attachment; filename*=UTF-8''" + urllib.parse.quote(path.name))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", ALLOWED_ORIGIN)
            self.send_header("Vary", "Origin")
            self.end_headers()
            try:
                with path.open("rb") as f:
                    shutil.copyfileobj(f, self.wfile, length=1024 * 1024)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self.send_json(404, {"error": "Not found"})

    def do_POST(self):
        if not self.authorized():
            return
        parsed = urllib.parse.urlsplit(self.path)
        data = self.read_body()
        if not isinstance(data, dict):
            self.send_json(400, {"error": "Invalid request body"})
            return
        if parsed.path == "/api/info":
            url = data.get("url")
            if not valid_public_url(url):
                self.send_json(400, {"error": "Enter a valid public HTTP(S) video link"})
                return
            try:
                ytdlp, _ = tools()
                result = subprocess.run([ytdlp, "--ignore-config", "--no-warnings", "--no-playlist",
                                         "--dump-single-json", "--skip-download", "--socket-timeout", "20", "--", url],
                                        capture_output=True, text=True, timeout=45,
                                        env={**os.environ, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"})
                if result.returncode:
                    self.send_json(422, {"error": "Could not read video details. It may be unsupported, private, or require sign-in."})
                    return
                meta = json.loads(result.stdout)
                self.send_json(200, {"title": str(meta.get("title") or "Untitled")[:300],
                                     "duration": meta.get("duration"),
                                     "thumbnail": meta.get("thumbnail") if str(meta.get("thumbnail", "")).startswith("https://") else None,
                                     "uploader": str(meta.get("uploader") or "")[:150],
                                     "formats": [{"height": x.get("height"), "ext": x.get("ext")}
                                                 for x in meta.get("formats", [])
                                                 if x.get("height") and x.get("height") <= 2160][:24]})
            except subprocess.TimeoutExpired:
                self.send_json(504, {"error": "The site took too long to respond"})
            except Exception as exc:
                self.send_json(500, {"error": str(exc)[:300]})
            return
        if parsed.path == "/api/download":
            url = data.get("url")
            quality = data.get("quality", "best")
            playlist = bool(data.get("playlist", False))
            if not valid_public_url(url):
                self.send_json(400, {"error": "Enter a valid public HTTP(S) video link"})
                return
            if quality not in ("best", "1080", "720", "audio"):
                self.send_json(400, {"error": "Unsupported quality"})
                return
            with LOCK:
                active = sum(1 for j in JOBS.values() if j.get("state") == "downloading")
                if active >= MAX_JOBS:
                    self.send_json(429, {"error": "Too many active downloads. Wait for one to finish."})
                    return
                job_id = secrets.token_hex(8)
                JOBS[job_id] = {"id": job_id, "state": "queued", "progress": 0,
                                "status": "Queued", "created": time.time(), "url": url, "log": ""}
            thread = threading.Thread(target=run_download, args=(job_id, url, quality, playlist), daemon=True)
            thread.start()
            self.send_json(202, {"id": job_id, "state": "queued", "status": "Queued"})
            return
        self.send_json(404, {"error": "Not found"})


def main():
    if os.name != "posix":
        raise SystemExit("This helper is for macOS.")
    token = get_token()
    try:
        tools()
    except Exception as exc:
        raise SystemExit(str(exc))
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("\nLinkDrop iPhone bridge is running locally.")
    print(f"Pairing token: {token}")
    print(f"Local endpoint: http://127.0.0.1:{PORT}")
    print("\nKeep this Terminal window open. For secure iPhone access, install Tailscale on both devices,")
    print(f"then run: tailscale serve --bg {PORT}")
    print("Stop with Control-C. Do not expose this port directly to the public internet.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping LinkDrop bridge…")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
