"""Testes unitários para o servidor/proxy de demonstração no PC."""

from __future__ import annotations

import http.client
import json
import sys
import tempfile
import threading
import unittest
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pc_web_demo  # noqa: E402


class _MockApiHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return

    def do_GET(self) -> None:
        if self.path == "/health":
            payload = json.dumps({"status": "ok"}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path == "/maps/current?v=1":
            if self.headers.get("If-None-Match") == '"etag-1"':
                self.send_response(304)
                self.send_header("ETag", '"etag-1"')
                self.end_headers()
                return
        self.send_response(404)
        self.end_headers()

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        raw = self.rfile.read(length)
        payload = json.dumps(
            {
                "path": self.path,
                "auth": self.headers.get("Authorization"),
                "body": json.loads(raw.decode("utf-8")),
            }
        ).encode("utf-8")
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class PcWebDemoTest(unittest.TestCase):
    def test_resolve_upstream_url_preserves_prefix_and_query(self) -> None:
        resolved = pc_web_demo.resolve_upstream_url(
            "https://granmap.example.org/api",
            "/api/maps/current?floor=1",
        )
        self.assertEqual(resolved.scheme, "https")
        self.assertEqual(resolved.netloc, "granmap.example.org")
        self.assertEqual(resolved.path, "/api/maps/current")
        self.assertEqual(resolved.query, "floor=1")

    def test_static_serving_redirect_and_api_proxy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "index.html").write_text("<html>GranMap</html>", encoding="utf-8")
            (root / "app.wasm").write_bytes(b"\x00asm")

            upstream = ThreadingHTTPServer(("127.0.0.1", 0), _MockApiHandler)
            upstream_thread = threading.Thread(target=upstream.serve_forever, daemon=True)
            upstream_thread.start()

            pc_web_demo.register_mime_types()
            handler = partial(
                pc_web_demo.GranMapDemoHandler,
                directory=str(root),
                api_url=f"http://127.0.0.1:{upstream.server_port}",
            )
            demo = ThreadingHTTPServer(("127.0.0.1", 0), handler)
            demo_thread = threading.Thread(target=demo.serve_forever, daemon=True)
            demo_thread.start()

            try:
                conn = http.client.HTTPConnection("127.0.0.1", demo.server_port, timeout=5)
                conn.request("GET", "/")
                r_root = conn.getresponse()
                r_root.read()
                self.assertEqual(r_root.status, 302)
                self.assertEqual(r_root.getheader("Location"), "/app/")

                conn.request("GET", "/app/app.wasm")
                r_wasm = conn.getresponse()
                self.assertEqual(r_wasm.read(), b"\x00asm")
                self.assertEqual(r_wasm.getheader("Content-Type"), "application/wasm")

                conn.request("GET", "/app/../../secret.txt")
                r_trav = conn.getresponse()
                self.assertEqual(r_trav.read().decode("utf-8"), "<html>GranMap</html>")

                conn.request("GET", "/api/health")
                r_health = conn.getresponse()
                self.assertEqual(r_health.status, 200)
                self.assertEqual(json.loads(r_health.read()), {"status": "ok"})

                conn.request(
                    "GET",
                    "/api/maps/current?v=1",
                    headers={"If-None-Match": '"etag-1"'},
                )
                r_304 = conn.getresponse()
                self.assertEqual(r_304.read(), b"")
                self.assertEqual(r_304.status, 304)

                conn.request(
                    "POST",
                    "/api/auth/login",
                    body=json.dumps({"email": "a@b.c"}),
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": "Bearer tok",
                    },
                )
                r_post = conn.getresponse()
                data = json.loads(r_post.read())
                self.assertEqual(r_post.status, 201)
                self.assertEqual(data["path"], "/auth/login")
                self.assertEqual(data["auth"], "Bearer tok")
                self.assertEqual(data["body"], {"email": "a@b.c"})
                conn.close()
            finally:
                demo.shutdown()
                demo.server_close()
                upstream.shutdown()
                upstream.server_close()


if __name__ == "__main__":
    unittest.main()
