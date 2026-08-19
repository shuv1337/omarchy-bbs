#!/usr/bin/env python3
"""Dependency-free Omarchy BBS server."""

from __future__ import annotations

import argparse
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import hmac
import html
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
import urllib.parse

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("OMARCHY_BBS_DB", ROOT / "bbs.db"))
SESSIONS: dict[str, tuple[int, float]] = {}
NONCES: dict[str, float] = {}

CSS = """
:root{color-scheme:dark;--bg:#0c0f0d;--panel:#151a16;--ink:#e8f3e9;--muted:#8fa091;--line:#2a352c;--hot:#a7f3a0;--amber:#f6c177}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace}main{width:min(880px,calc(100% - 28px));margin:auto}.mast{border-bottom:1px solid var(--line);padding:28px 0 18px;display:flex;justify-content:space-between;align-items:end}.brand{font-size:clamp(24px,6vw,48px);font-weight:900;letter-spacing:-.08em;color:var(--hot)}.tag,.meta{color:var(--muted);font-size:13px}.nav{padding:14px 0;display:flex;gap:18px}.nav a,a{color:var(--hot);text-decoration:none}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;margin:14px 0;padding:18px}.thread{display:grid;grid-template-columns:1fr auto;gap:8px}.thread h2{font-size:18px;margin:0}.body{white-space:pre-wrap;margin-top:12px}form{display:grid;gap:10px}input,textarea,button{font:inherit;color:var(--ink);background:#0f1310;border:1px solid var(--line);border-radius:5px;padding:10px}textarea{min-height:110px;resize:vertical}button{width:max-content;background:var(--hot);color:#101510;border:0;font-weight:800;cursor:pointer}.badge{color:var(--amber)}footer{color:var(--muted);padding:30px 0 50px;text-align:center}@media(max-width:560px){.mast{align-items:start;flex-direction:column;gap:8px}.thread{grid-template-columns:1fr}}
"""


def db() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


def initialize() -> None:
    with db() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, handle TEXT UNIQUE NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), secret_hash TEXT NOT NULL, omarchy_version TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS invites(code_hash TEXT PRIMARY KEY, uses_left INTEGER NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS threads(id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), title TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS replies(id INTEGER PRIMARY KEY, thread_id INTEGER NOT NULL REFERENCES threads(id), user_id INTEGER NOT NULL REFERENCES users(id), body TEXT NOT NULL, created_at INTEGER NOT NULL);
        """)


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def page(title: str, handle: str, content: str) -> bytes:
    return f"""<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>{esc(title)} · Omarchy BBS</title><style>{CSS}</style></head><body><main><header class=mast><div><div class=brand>OMARCHY//BBS</div><div class=tag>local machines. shared frequency.</div></div><div class=meta>linked as <span class=badge>@{esc(handle)}</span></div></header><nav class=nav><a href='/'>[ threads ]</a><a href='/new'>[ new transmission ]</a><a href='/logout'>[ disconnect ]</a></nav>{content}<footer>ACCESS GRANTED VIA OMARCHY DEVICE CREDENTIAL</footer></main></body></html>""".encode()


class Handler(BaseHTTPRequestHandler):
    server_version = "OmarchyBBS/0.1"

    def send(self, status: int, body: bytes, content_type="text/html; charset=utf-8", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
        for key, value in headers or []:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def json(self, status: int, payload: dict):
        self.send(status, json.dumps(payload).encode(), "application/json")

    def redirect(self, location: str, session: str | None = None):
        headers = [("Location", location)]
        if session:
            headers.append(("Set-Cookie", f"bbs_session={session}; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400"))
        self.send(303, b"", headers=headers)

    def user(self):
        jar = cookies.SimpleCookie(self.headers.get("Cookie"))
        token = jar.get("bbs_session")
        record = SESSIONS.get(token.value) if token else None
        if not record or record[1] < time.time():
            return None
        with db() as conn:
            return conn.execute("SELECT * FROM users WHERE id=?", (record[0],)).fetchone()

    def form(self):
        length = int(self.headers.get("Content-Length", "0"))
        return urllib.parse.parse_qs(self.rfile.read(length).decode(), keep_blank_values=True)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/auth":
            return self.authenticate(urllib.parse.parse_qs(parsed.query))
        if parsed.path == "/logout":
            jar = cookies.SimpleCookie(self.headers.get("Cookie"))
            if jar.get("bbs_session"):
                SESSIONS.pop(jar["bbs_session"].value, None)
            return self.redirect("/")
        user = self.user()
        if not user:
            return self.send(401, b"Omarchy device authentication required. Open this BBS from its Omarchy bar widget.", "text/plain; charset=utf-8")
        if parsed.path == "/":
            return self.index(user)
        if parsed.path == "/new":
            content = "<section class=card><h1>New transmission</h1><form method=post action=/new><input name=title maxlength=120 required placeholder='Subject'><textarea name=body maxlength=8000 required placeholder='Write something worth reading.'></textarea><button>Transmit</button></form></section>"
            return self.send(200, page("New transmission", user["handle"], content))
        if parsed.path.startswith("/thread/"):
            try: thread_id = int(parsed.path.rsplit("/", 1)[1])
            except ValueError: return self.send(404, b"Not found", "text/plain")
            return self.thread(user, thread_id)
        return self.send(404, b"Not found", "text/plain")

    def authenticate(self, query):
        try:
            device, ts, nonce, sig = (query[k][0] for k in ("device", "ts", "nonce", "sig"))
            timestamp = int(ts)
        except (KeyError, ValueError):
            return self.send(400, b"Invalid login link", "text/plain")
        now = time.time()
        for used_nonce, expiry in list(NONCES.items()):
            if expiry <= now:
                NONCES.pop(used_nonce, None)
        if abs(now - timestamp) > 60 or nonce in NONCES:
            return self.send(401, b"Login link expired or already used", "text/plain")
        with db() as conn:
            row = conn.execute("SELECT user_id, secret_hash FROM devices WHERE id=?", (device,)).fetchone()
        if not row:
            return self.send(401, b"Unknown device", "text/plain")
        expected = hmac.new(bytes.fromhex(row["secret_hash"]), f"{device}.{ts}.{nonce}".encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, sig):
            return self.send(401, b"Invalid device proof", "text/plain")
        NONCES[nonce] = now + 120
        token = secrets.token_urlsafe(32)
        SESSIONS[token] = (row["user_id"], now + 86400)
        self.redirect("/", token)

    def index(self, user):
        with db() as conn:
            rows = conn.execute("""SELECT t.id,t.title,t.created_at,u.handle,COUNT(r.id) replies FROM threads t JOIN users u ON u.id=t.user_id LEFT JOIN replies r ON r.thread_id=t.id GROUP BY t.id ORDER BY t.id DESC""").fetchall()
        cards = "".join(f"<article class='card thread'><div><h2><a href='/thread/{r['id']}'>{esc(r['title'])}</a></h2><div class=meta>@{esc(r['handle'])} · {time.strftime('%Y-%m-%d %H:%M', time.localtime(r['created_at']))}</div></div><div class=badge>{r['replies']} repl.</div></article>" for r in rows)
        content = cards or "<section class=card>No transmissions yet. You have the channel.</section>"
        self.send(200, page("Threads", user["handle"], content))

    def thread(self, user, thread_id):
        with db() as conn:
            thread = conn.execute("SELECT t.*,u.handle FROM threads t JOIN users u ON u.id=t.user_id WHERE t.id=?", (thread_id,)).fetchone()
            replies = conn.execute("SELECT r.*,u.handle FROM replies r JOIN users u ON u.id=r.user_id WHERE thread_id=? ORDER BY r.id", (thread_id,)).fetchall()
        if not thread: return self.send(404, b"Not found", "text/plain")
        content = f"<article class=card><h1>{esc(thread['title'])}</h1><div class=meta>@{esc(thread['handle'])}</div><div class=body>{esc(thread['body'])}</div></article>"
        content += "".join(f"<article class=card><div class=meta>@{esc(r['handle'])}</div><div class=body>{esc(r['body'])}</div></article>" for r in replies)
        content += f"<section class=card><form method=post action='/thread/{thread_id}'><textarea name=body maxlength=8000 required placeholder='Reply on this frequency'></textarea><button>Reply</button></form></section>"
        self.send(200, page(thread["title"], user["handle"], content))

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/enroll":
            return self.enroll()
        user = self.user()
        if not user: return self.send(401, b"Authentication required", "text/plain")
        form = self.form()
        if parsed.path == "/new":
            title, body = form.get("title", [""])[0].strip(), form.get("body", [""])[0].strip()
            if not title or not body: return self.send(400, b"Title and body required", "text/plain")
            with db() as conn:
                cursor = conn.execute("INSERT INTO threads(user_id,title,body,created_at) VALUES(?,?,?,?)", (user["id"], title[:120], body[:8000], int(time.time())))
            return self.redirect(f"/thread/{cursor.lastrowid}")
        if parsed.path.startswith("/thread/"):
            try: thread_id = int(parsed.path.rsplit("/", 1)[1])
            except ValueError: return self.send(404, b"Not found", "text/plain")
            body = form.get("body", [""])[0].strip()
            if not body: return self.send(400, b"Reply required", "text/plain")
            with db() as conn:
                conn.execute("INSERT INTO replies(thread_id,user_id,body,created_at) VALUES(?,?,?,?)", (thread_id, user["id"], body[:8000], int(time.time())))
            return self.redirect(f"/thread/{thread_id}")
        self.send(404, b"Not found", "text/plain")

    def enroll(self):
        length = int(self.headers.get("Content-Length", "0"))
        try: payload = json.loads(self.rfile.read(length))
        except Exception: return self.json(400, {"error": "Invalid JSON"})
        invite_hash = hashlib.sha256(str(payload.get("invite", "")).encode()).hexdigest()
        handle = str(payload.get("handle", "")).strip().lower()
        version = str(payload.get("omarchy_version", ""))[:80]
        if not handle.replace("-", "").replace("_", "").isalnum() or not (2 <= len(handle) <= 24):
            return self.json(400, {"error": "Handle must be 2-24 letters, numbers, hyphens, or underscores"})
        if not version: return self.json(400, {"error": "Omarchy version missing"})
        secret, device_id = secrets.token_hex(32), secrets.token_urlsafe(16)
        with db() as conn:
            invite = conn.execute("SELECT uses_left FROM invites WHERE code_hash=?", (invite_hash,)).fetchone()
            if not invite or invite["uses_left"] < 1: return self.json(403, {"error": "Invalid or exhausted invite"})
            conn.execute("INSERT OR IGNORE INTO users(handle,created_at) VALUES(?,?)", (handle, int(time.time())))
            user = conn.execute("SELECT id FROM users WHERE handle=?", (handle,)).fetchone()
            conn.execute("INSERT INTO devices VALUES(?,?,?,?,?)", (device_id, user["id"], secret, version, int(time.time())))
            conn.execute("UPDATE invites SET uses_left=uses_left-1 WHERE code_hash=?", (invite_hash,))
        self.json(201, {"device_id": device_id, "secret": secret, "handle": handle})

    def log_message(self, format, *args):
        print(f"{self.client_address[0]} - {format % args}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")
    serve = sub.add_parser("serve")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8787)
    invite = sub.add_parser("invite")
    invite.add_argument("--uses", type=int, default=1)
    args = parser.parse_args()
    initialize()
    if args.command == "invite":
        code = secrets.token_urlsafe(18)
        with db() as conn:
            conn.execute("INSERT INTO invites VALUES(?,?,?)", (hashlib.sha256(code.encode()).hexdigest(), max(1,args.uses), int(time.time())))
        print(code)
        return
    if args.command != "serve": parser.error("choose serve or invite")
    print(f"Omarchy BBS listening on http://{args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__": main()
