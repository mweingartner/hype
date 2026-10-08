#!/usr/bin/python3
"""Exercise Hype's real HTTP transport against a private, credential-free fixture."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import os
import subprocess
import threading
import time


class Handler(BaseHTTPRequestHandler):
    expired = False
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        method = request["method"]
        if self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/should-not-follow")
            self.end_headers()
            return
        if method == "initialize":
            result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}}
        elif method == "notifications/initialized":
            self.send_response(202)
            self.end_headers()
            return
        elif self.path == "/stall":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.flush()
            time.sleep(10)
            return
        elif self.path == "/expired":
            with self.lock:
                first = not Handler.expired
                Handler.expired = True
            if first:
                self.send_response(404)
                self.end_headers()
                return
            result = {"tools": []}
        else:
            result = {"tools": []}
        payload = json.dumps({"jsonrpc": "2.0", "id": request.get("id"), "result": result}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Mcp-Session-Id", "fixture")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        environment = dict(os.environ, HYPE_BRAVE_FIXTURE_URL=f"http://127.0.0.1:{server.server_port}")
        result = subprocess.run([str(root / "scripts/test.sh"), "--filter", "HypeMCPHTTPClientTests"], cwd=root, env=environment)
    finally:
        server.shutdown()
        server.server_close()
    raise SystemExit(result.returncode)
