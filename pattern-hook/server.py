#!/usr/bin/env python3
"""
Minimal HTTP receiver for ae2Colony missing-pattern webhooks.

Run on the same host as the Minecraft server (127.0.0.1). See README.md.
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

HOST = os.environ.get("AE2COLONY_HOOK_HOST", "127.0.0.1")
PORT = int(os.environ.get("AE2COLONY_HOOK_PORT", "8099"))
SECRET = os.environ.get("AE2COLONY_HOOK_SECRET", "").strip()
QUEUE = os.environ.get("AE2COLONY_HOOK_QUEUE", "missing_patterns_queue.jsonl")


class Handler(BaseHTTPRequestHandler):
    server_version = "ae2colony-pattern-hook/1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _read_json_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > 65536:
            return None
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        if not isinstance(data, dict):
            return None
        return data

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0].rstrip("/")
        if path != "/ae2colony/missing":
            self.send_error(404, "Not Found")
            return

        if SECRET:
            got = (self.headers.get("X-AE2Colony-Secret") or "").strip()
            if got != SECRET:
                self.send_error(401, "Unauthorized")
                return

        body = self._read_json_body()
        if body is None:
            self.send_error(400, "Bad JSON")
            return

        line = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
        with open(QUEUE, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")

        self.send_response(204)
        self.end_headers()


def main() -> int:
    httpd = HTTPServer((HOST, PORT), Handler)
    print("ae2colony pattern hook listening on http://%s:%s%s" % (HOST, PORT, "/ae2colony/missing"))
    print("queue file:", os.path.abspath(QUEUE))
    if not SECRET:
        print("warning: AE2COLONY_HOOK_SECRET is empty; set it for production", file=sys.stderr)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
