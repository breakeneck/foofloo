#!/usr/bin/env python3
"""Tiny LAN crash-report collector for the FooFlo debug APK.

POST /report  {"device": str, "lines": [str]}  -> appended to a log file
GET  /ping    -> {"ok": true}

Stdlib-only, no auth: bind to a LAN address only, never WAN.
"""

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = os.environ.get("FOOFLOO_REPORT_LOG", os.path.expanduser("~/dev/foofloo/reports.log"))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path == "/ping":
            self._send(200, {"ok": True})
        else:
            self._send(404, {"ok": False})

    def do_POST(self):
        if self.path != "/report":
            self._send(404, {"ok": False})
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            data = json.loads(self.rfile.read(n).decode("utf-8", "replace"))
        except Exception:
            self._send(400, {"ok": False, "error": "bad json"})
            return
        lines = data.get("lines") or []
        device = str(data.get("device", "?"))[:64]
        with open(LOG, "a") as f:
            f.write("=== %s :: %s :: %d lines ===\n" % (time.strftime("%F %T"), device, len(lines)))
            for ln in lines:
                f.write("  %s\n" % str(ln)[:500])
        print("[report] %s: %d lines" % (device, len(lines)), flush=True)
        self._send(200, {"ok": True})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 45699
    bind = sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0"
    ThreadingHTTPServer((bind, port), Handler).serve_forever()


if __name__ == "__main__":
    main()