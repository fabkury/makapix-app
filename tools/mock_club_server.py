#!/usr/bin/env python3
"""Mock Makapix Club server for testing the in-app upload (SPEC §21/§28.7).

Run:  python tools/mock_club_server.py   (listens on http://localhost:8080)
Then in the app's Upload dialog set Server base URL = http://localhost:8080 and any token.
It accepts POST /api/v1/artifacts (multipart) and saves the artifact under tools/uploads/.
"""
import http.server
import json
import os
import time

UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/v1/me":
            self._json(200, {"user": "mock", "ok": True})
        else:
            self._json(404, {"error": {"code": "not_found", "message": self.path}})

    def do_POST(self):
        if self.path != "/api/v1/artifacts":
            return self._json(404, {"error": {"code": "not_found", "message": self.path}})
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        auth = self.headers.get("Authorization", "(none)")
        # naive: just persist the whole multipart body for inspection
        ts = int(time.time())
        path = os.path.join(UPLOAD_DIR, f"upload_{ts}.bin")
        with open(path, "wb") as f:
            f.write(body)
        print(f"[mock-club] received {length} bytes, auth={auth} -> {path}")
        self._json(200, {"id": f"mock-{ts}", "url": f"https://makapix.club/p/mock-{ts}"})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("[mock-club] listening on http://localhost:8080  (POST /api/v1/artifacts)")
    http.server.HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
