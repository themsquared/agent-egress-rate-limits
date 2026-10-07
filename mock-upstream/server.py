#!/usr/bin/env python3
"""Deterministic stand-in for a public third-party API (e.g. Wikidata Query
Service). It answers every request and counts how many it actually received,
so the demo can prove how much traffic reached it with and without a gateway
rate-limit policy in front of it."""
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MOCK_PORT", "8090"))

_lock = threading.Lock()
_count = 0
_started = time.time()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # quiet; scripts/demo.sh prints what matters

    def _json(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        global _count
        if self.path == "/stats":
            with _lock:
                self._json(200, {"requests_received": _count, "uptime_s": round(time.time() - _started, 1)})
            return
        if self.path == "/reset":
            with _lock:
                _count = 0
            self._json(200, {"reset": True})
            return
        # /sparql or /query or anything else: simulate a real query response
        with _lock:
            _count += 1
            n = _count
        self._json(200, {"query_id": n, "results": {"bindings": []}})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"mock-upstream listening on :{PORT}")
    server.serve_forever()
