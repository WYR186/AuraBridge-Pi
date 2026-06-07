#!/usr/bin/env python3
"""Small dependency-free preview server for the AuraBridge dashboard."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SAMPLE_STATUS = ROOT / "data" / "status.sample.json"


class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path == "/api/status":
            self.send_status()
            return
        super().do_GET()

    def send_status(self):
        with SAMPLE_STATUS.open("r", encoding="utf-8") as source:
            payload = json.load(source)
        payload["generated_at"] = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")

        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description="Serve the AuraBridge dashboard.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8080, type=int)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), DashboardHandler)
    print(f"AuraBridge Dashboard: http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
