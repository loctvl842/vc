#!/usr/bin/env python3
"""Local review loop for a spec HTML file (pm-spec or dev-spec). Standard library only.

    review.py serve FILE [--port N] [--open]   serve FILE with the review panel (run in background)
    review.py poll  FILE [--wait SECONDS]      block until the user sends feedback or approves, print it
    review.py reply FILE TEXT                  post an agent reply into the panel's conversation
    review.py status FILE                      show whether a server is running for FILE
    review.py stop  FILE                       stop the server

The human opens the served page, clicks elements or selects text to leave notes, and sends them. The agent
`poll`s, receives the notes (with CSS selector, nearest data-spec id and quoted text), edits the spec, saves the
file (the page live-reloads), and `reply`s. State lives in `<dir of FILE>/.review/<stem>/` (git-ignored).
"""

import argparse
import json
import mimetypes
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

SDK_PATH = Path(__file__).with_name("review_sdk.js")
POLL_SLICE = 20.0  # seconds a single server-side long poll may block
LISTEN_GRACE = 8.0  # seconds after a poll ends before the agent counts as not listening


# -- state --------------------------------------------------------------------------------------------------------


def state_dir(file: Path) -> Path:
    path = file.parent / ".review" / file.stem
    path.mkdir(parents=True, exist_ok=True)
    gitignore = file.parent / ".review" / ".gitignore"
    if not gitignore.exists():
        gitignore.write_text("*\n")
    return path


def read_info(file: Path) -> dict | None:
    try:
        return json.loads((state_dir(file) / "server.json").read_text())
    except (FileNotFoundError, ValueError):
        return None


def call(info: dict, method: str, path: str, body: dict | None = None, timeout: float = 5.0) -> dict:
    req = urllib.request.Request(
        f"http://127.0.0.1:{info['port']}/__review/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"X-Review-Token": info["token"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return json.loads(res.read())


def live_info(file: Path) -> dict | None:
    info = read_info(file)
    if info is None:
        return None
    try:
        call(info, "GET", "state", timeout=2)
    except (urllib.error.URLError, OSError, ValueError):
        return None
    return info


class Session:
    def __init__(self, file: Path, token: str, log: Path):
        self.file = file
        self.token = token
        self.log = log
        self.cond = threading.Condition()
        self.messages: list[dict] = []
        self.pending: list[dict] = []
        self.approved = False
        self.active_polls = 0
        self.last_poll = 0.0
        self.next_id = 1
        self.stopping = False

    def add_message(self, role: str, **fields) -> dict:
        msg = {"id": self.next_id, "role": role, "ts": time.time(), "delivered": role == "agent", **fields}
        self.next_id += 1
        self.messages.append(msg)
        with self.log.open("a") as out:
            out.write(json.dumps(msg) + "\n")
        return msg

    def snapshot(self) -> dict:
        with self.cond:
            listening = self.active_polls > 0 or time.time() - self.last_poll < LISTEN_GRACE
            return {
                "mtime": self.file.stat().st_mtime_ns if self.file.exists() else 0,
                "messages": list(self.messages),
                "listening": listening,
                "approved": self.approved,
            }


# -- http ---------------------------------------------------------------------------------------------------------


def inject(html: str, token: str) -> str:
    tag = f'<script>window.__REVIEW_TOKEN={json.dumps(token)}</script><script src="/__review/sdk.js"></script>'
    i = html.lower().rfind("</body>")
    return html[:i] + tag + html[i:] if i != -1 else html + tag


def make_handler(session: Session, port: int):
    allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
    root = session.file.parent.resolve()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_args):
            pass

        def send_bytes(self, status: int, body: bytes, ctype: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def send_json(self, data: dict, status: int = 200) -> None:
            self.send_bytes(status, json.dumps(data).encode(), "application/json")

        def host_ok(self) -> bool:
            return self.headers.get("Host", "") in allowed_hosts

        def api_ok(self) -> bool:
            # Custom header forces a CORS preflight, which this server never answers, so other origins cannot call it.
            return self.host_ok() and self.headers.get("X-Review-Token") == session.token

        def body(self) -> dict:
            length = int(self.headers.get("Content-Length") or 0)
            if length > 1_000_000:
                raise ValueError("body too large")
            return json.loads(self.rfile.read(length) or b"{}")

        def do_GET(self) -> None:
            if not self.host_ok():
                return self.send_json({"error": "bad host"}, 403)
            url = urlparse(self.path)
            if url.path == "/__review/sdk.js":
                return self.send_bytes(200, SDK_PATH.read_bytes(), "application/javascript")
            if url.path.startswith("/__review/"):
                if not self.api_ok():
                    return self.send_json({"error": "forbidden"}, 403)
                if url.path == "/__review/state":
                    return self.send_json(session.snapshot())
                if url.path == "/__review/poll":
                    wait = float(parse_qs(url.query).get("timeout", ["20"])[0])
                    return self.send_json(self.long_poll(min(wait, POLL_SLICE)))
                return self.send_json({"error": "not found"}, 404)
            if url.path == "/":
                html = session.file.read_text(encoding="utf-8")
                return self.send_bytes(200, inject(html, session.token).encode(), "text/html; charset=utf-8")
            # Sibling assets (images, css), confined to the spec's directory and never the state dir.
            target = (root / url.path.lstrip("/")).resolve()
            if root not in target.parents or ".review" in target.relative_to(root).parts or not target.is_file():
                return self.send_json({"error": "not found"}, 404)
            ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            return self.send_bytes(200, target.read_bytes(), ctype)

        def do_POST(self) -> None:
            if not self.api_ok():
                return self.send_json({"error": "forbidden"}, 403)
            path = urlparse(self.path).path
            try:
                data = self.body()
            except ValueError as e:
                return self.send_json({"error": str(e)}, 400)
            if path == "/__review/feedback":
                items = [i for i in data.get("items", []) if str(i.get("note", "")).strip()]
                text = str(data.get("message", "")).strip()
                approve = bool(data.get("approve"))
                if not (items or text or approve):
                    return self.send_json({"error": "empty"}, 400)
                with session.cond:
                    session.add_message("user", items=items, text=text, approve=approve)
                    session.pending.append({"items": items, "text": text, "approve": approve})
                    session.approved = session.approved or approve
                    session.cond.notify_all()
                return self.send_json({"ok": True})
            if path == "/__review/reply":
                with session.cond:
                    session.add_message("agent", text=str(data.get("text", "")))
                return self.send_json({"ok": True})
            if path == "/__review/end":
                session.stopping = True
                self.send_json({"ok": True})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            return self.send_json({"error": "not found"}, 404)

        def long_poll(self, wait: float) -> dict:
            deadline = time.time() + wait
            with session.cond:
                session.active_polls += 1
                session.last_poll = time.time()
                try:
                    while not session.pending and not session.stopping:
                        left = deadline - time.time()
                        if left <= 0:
                            return {"status": "waiting"}
                        session.cond.wait(left)
                    batches, session.pending = session.pending, []
                    for msg in session.messages:
                        if msg["role"] == "user":
                            msg["delivered"] = True
                    return {"status": "feedback", "batches": batches, "approved": session.approved}
                finally:
                    session.active_polls -= 1
                    session.last_poll = time.time()

    return Handler


# -- commands -----------------------------------------------------------------------------------------------------


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def cmd_serve(args) -> int:
    file = Path(args.file).resolve()
    if file.suffix != ".html" or not file.is_file():
        print(f"error: {file} is not an existing .html file", file=sys.stderr)
        return 2
    existing = live_info(file)
    if existing:
        print(f"already running: http://127.0.0.1:{existing['port']}/")
        return 0
    sdir = state_dir(file)
    port = args.port or free_port()
    session = Session(file, secrets.token_urlsafe(24), sdir / "conversation.jsonl")
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(session, port))
    server.daemon_threads = True
    info_path = sdir / "server.json"
    info_path.write_text(json.dumps({"port": port, "token": session.token, "pid": os.getpid(), "file": str(file)}))
    info_path.chmod(0o600)
    url = f"http://127.0.0.1:{port}/"
    print(f"serving {file.name} at {url}", flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        info_path.unlink(missing_ok=True)
    return 0


def format_feedback(result: dict) -> str:
    lines = []
    for batch in result["batches"]:
        for i, item in enumerate(batch["items"], 1):
            where = item.get("spec") or "(no data-spec)"
            lines.append(f"[{i}] spec={where}  selector={item.get('selector', '')}")
            if item.get("quote"):
                lines.append(f'    quote: "{item["quote"]}"')
            lines.append(f"    note: {item['note']}")
        if batch["text"]:
            lines.append(f"message: {batch['text']}")
        if batch["approve"]:
            lines.append("APPROVED")
    return "\n".join(lines)


def cmd_poll(args) -> int:
    file = Path(args.file).resolve()
    info = live_info(file)
    if not info:
        print("error: no review server running; start one with `serve`", file=sys.stderr)
        return 2
    deadline = time.time() + args.wait
    while time.time() < deadline:
        try:
            result = call(info, "GET", f"poll?timeout={POLL_SLICE}", timeout=POLL_SLICE + 10)
        except (urllib.error.URLError, OSError):
            print("error: review server stopped", file=sys.stderr)
            return 3
        if result["status"] == "feedback":
            print("review: approved" if result["approved"] else "review: feedback")
            print(format_feedback(result))
            return 0
    print("review: waiting (no feedback yet)")
    return 0


def cmd_reply(args) -> int:
    info = live_info(Path(args.file).resolve())
    if not info:
        print("error: no review server running", file=sys.stderr)
        return 2
    call(info, "POST", "reply", {"text": args.text})
    return 0


def cmd_status(args) -> int:
    info = live_info(Path(args.file).resolve())
    if not info:
        print("not running")
        return 1
    snap = call(info, "GET", "state")
    print(f"running http://127.0.0.1:{info['port']}/ listening={snap['listening']} approved={snap['approved']}")
    return 0


def cmd_stop(args) -> int:
    info = live_info(Path(args.file).resolve())
    if info:
        call(info, "POST", "end", {})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("serve")
    s.add_argument("file")
    s.add_argument("--port", type=int, default=0)
    s.add_argument("--open", action="store_true", help="open the page in the default browser")
    s.set_defaults(fn=cmd_serve)
    p = sub.add_parser("poll")
    p.add_argument("file")
    p.add_argument("--wait", type=float, default=1800, help="give up after this many seconds")
    p.set_defaults(fn=cmd_poll)
    r = sub.add_parser("reply")
    r.add_argument("file")
    r.add_argument("text")
    r.set_defaults(fn=cmd_reply)
    for name, fn in (("status", cmd_status), ("stop", cmd_stop)):
        c = sub.add_parser(name)
        c.add_argument("file")
        c.set_defaults(fn=fn)
    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
