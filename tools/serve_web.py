#!/usr/bin/env python3
"""Serve builds/web like a static host would, but with Cache-Control: no-store
on everything, so a service-worker update check always sees the freshest file
-- the stand-in for 'a deploy just happened' in the update-flow test."""
import http.server
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "builds", "web"))

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wasm": "application/wasm",
    ".gz": "application/gzip",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".mp3": "audio/mpeg",
    ".css": "text/css; charset=utf-8",
    ".woff2": "font/woff2",
}


class NoStore(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def guess_type(self, path):
        for ext, mime in TYPES.items():
            if path.endswith(ext):
                return mime
        return "application/octet-stream"


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    os.chdir(ROOT)
    print(f"serving {ROOT} at http://127.0.0.1:{port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), NoStore).serve_forever()
