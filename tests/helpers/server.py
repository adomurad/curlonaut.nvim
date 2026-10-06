#!/usr/bin/env python3
"""Tiny mock HTTP server used by the curlonaut.nvim end-to-end tests.

Listens on an ephemeral port on 127.0.0.1 and prints ``PORT=<port>`` on stdout
so the Lua test helper can discover it. Every response body is JSON unless
noted otherwise.
"""

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

JSON_RESPONSE = {
    "token": "abc123",
    "items": [{"id": 7}, {"id": 8}],
    "nested": {"ok": True},
}

HITS = {"count": 0}
HITS_LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # silence request logging
        pass

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return b""
        return self.rfile.read(length)

    def _send(self, status, payload, content_type="application/json", extra_headers=None):
        if isinstance(payload, (dict, list)):
            body = json.dumps(payload).encode("utf-8")
        elif isinstance(payload, str):
            body = payload.encode("utf-8")
        else:
            body = payload
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _echo(self):
        raw = self._read_body()
        headers = {key.lower(): value for key, value in self.headers.items()}
        self._send(
            200,
            {
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("Content-Type"),
                "headers": headers,
                "body": raw.decode("utf-8", errors="replace"),
            },
        )

    def _handle(self):
        parsed = urlparse(self.path)
        route = parsed.path

        if route == "/__hits":
            with HITS_LOCK:
                count = HITS["count"]
            self._send(200, {"count": count})
            return
        if route == "/__reset":
            with HITS_LOCK:
                HITS["count"] = 0
            self._send(200, {"ok": True})
            return

        with HITS_LOCK:
            HITS["count"] += 1

        if route == "/echo":
            self._echo()
        elif route == "/json":
            self._send(200, JSON_RESPONSE)
        elif route == "/with-header":
            self._send(
                200,
                {"ok": True},
                extra_headers={"X-Request-Id": "req-abc-123"},
            )
        elif route == "/text":
            self._send(200, "plain text response", content_type="text/plain")
        elif route == "/set-cookie":
            self._send(
                200,
                {"ok": True},
                extra_headers={"Set-Cookie": "session=xyz; Path=/"},
            )
        elif route == "/check-cookie":
            self._send(200, {"cookie": self.headers.get("Cookie") or ""})
        elif route == "/slow":
            ms = int((parse_qs(parsed.query).get("ms") or ["1000"])[0])
            time.sleep(ms / 1000.0)
            self._send(200, {"slept": ms})
        else:
            self._send(404, {"error": "not found", "path": self.path})

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def do_PUT(self):
        self._handle()

    def do_PATCH(self):
        self._handle()

    def do_DELETE(self):
        self._handle()

    def handle_expect_100(self):
        # curl sends Expect: 100-continue for larger bodies; accept it.
        self.send_response_only(100)
        self.end_headers()
        return True


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    print(f"PORT={port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
