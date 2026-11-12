"""Servidor local leve para abrir e demonstrar o GranMap no PC via navegador."""

from __future__ import annotations

import argparse
import http.client
import mimetypes
import os
import posixpath
import shutil
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_API_URL = "http://127.0.0.1:8787/api"
LOCAL_API_URL = "http://127.0.0.1:8100"
REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
BACKEND_DIR = REPO_ROOT / "backend"
WEB_BUILD_DIR = APP_DIR / "build" / "web"

HOP_BY_HOP_HEADERS = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    }
)

NO_CACHE_NAMES = frozenset(
    {
        "index.html",
        "flutter_bootstrap.js",
        "flutter_service_worker.js",
        "version.json",
        "manifest.json",
    }
)


def register_mime_types() -> None:
    """Garante Content-Types exigidos pelo runtime CanvasKit/WASM do Flutter Web."""
    mimetypes.init()
    for ext, mime in (
        (".wasm", "application/wasm"),
        (".mjs", "application/javascript"),
        (".js", "application/javascript"),
        (".json", "application/json"),
        (".otf", "font/otf"),
        (".ttf", "font/ttf"),
        (".svg", "image/svg+xml"),
    ):
        mimetypes.add_type(mime, ext)


def ensure_web_build(*, rebuild: bool = False) -> Path:
    """Garante que app/build/web esteja compilado para /app/ com API em /api."""
    index_file = WEB_BUILD_DIR / "index.html"
    if index_file.is_file() and not rebuild:
        return WEB_BUILD_DIR

    flutter_cmd = shutil.which("flutter") or shutil.which("flutter.bat")
    if not flutter_cmd:
        raise RuntimeError(
            "Build Web ausente em app/build/web e comando 'flutter' não encontrado."
        )

    print("Compilando versão Web de demonstração do GranMap...")
    subprocess.run(
        [
            flutter_cmd,
            "build",
            "web",
            "--release",
            "--dart-define=GRANMAP_API_URL=/api",
            "--base-href=/app/",
        ],
        cwd=APP_DIR,
        check=True,
    )
    if not index_file.is_file():
        raise RuntimeError("Falha ao gerar app/build/web/index.html.")
    return WEB_BUILD_DIR


def resolve_upstream_url(base_api_url: str, request_target: str) -> urllib.parse.ParseResult:
    """Combina a URL base da API configurada com o caminho /api/... recebido."""
    parsed_target = urllib.parse.urlsplit(request_target)
    suffix = parsed_target.path
    if suffix == "/api":
        suffix = ""
    elif suffix.startswith("/api/"):
        suffix = suffix[len("/api") :]

    base = base_api_url.rstrip("/")
    full = f"{base}{suffix}"
    if parsed_target.query:
        full = f"{full}?{parsed_target.query}"
    return urllib.parse.urlparse(full)


class GranMapDemoHandler(SimpleHTTPRequestHandler):
    """Serve o Flutter Web em /app/ e faz proxy reverso de /api/ sem erros de CORS."""

    def __init__(
        self,
        *args,
        directory: str,
        api_url: str,
        **kwargs,
    ) -> None:
        self.api_url = api_url
        super().__init__(*args, directory=directory, **kwargs)

    def end_headers(self) -> None:
        name = posixpath.basename(urllib.parse.urlsplit(self.path).path)
        if not name or name in NO_CACHE_NAMES:
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return

    def do_GET(self) -> None:
        if self._maybe_proxy():
            return
        if self._maybe_redirect_root():
            return
        self._rewrite_app_path()
        super().do_GET()

    def do_HEAD(self) -> None:
        if self._maybe_proxy():
            return
        if self._maybe_redirect_root():
            return
        self._rewrite_app_path()
        super().do_HEAD()

    def do_POST(self) -> None:
        if not self._maybe_proxy():
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_PUT(self) -> None:
        if not self._maybe_proxy():
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_DELETE(self) -> None:
        if not self._maybe_proxy():
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_OPTIONS(self) -> None:
        if self._maybe_proxy():
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.end_headers()

    def _maybe_redirect_root(self) -> bool:
        path = urllib.parse.urlsplit(self.path).path
        if path in ("", "/", "/app"):
            self.send_response(HTTPStatus.FOUND)
            self.send_header("Location", "/app/")
            self.end_headers()
            return True
        return False

    def _rewrite_app_path(self) -> None:
        split = urllib.parse.urlsplit(self.path)
        rel = split.path
        if rel.startswith("/app/"):
            rel = rel[len("/app") :]
        elif rel == "/app":
            rel = "/"

        base_dir = Path(self.directory).resolve()
        safe_rel = posixpath.normpath(rel).lstrip("/")
        candidate = (base_dir / safe_rel).resolve() if safe_rel else base_dir
        if not candidate.is_relative_to(base_dir):
            rel = "/index.html"
        elif safe_rel and not candidate.exists():
            rel = "/index.html"
        elif rel == "/":
            rel = "/index.html"
        self.path = urllib.parse.urlunsplit(("", "", rel, split.query, ""))

    def _maybe_proxy(self) -> bool:
        path = urllib.parse.urlsplit(self.path).path
        if path != "/api" and not path.startswith("/api/"):
            return False

        upstream = resolve_upstream_url(self.api_url, self.path)
        content_len = int(self.headers.get("Content-Length") or "0")
        body = self.rfile.read(content_len) if content_len > 0 else None

        forward_headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_BY_HOP_HEADERS or lower in ("host", "content-length"):
                continue
            forward_headers[key] = value
        forward_headers["Host"] = upstream.netloc

        target_path = upstream.path or "/"
        if upstream.query:
            target_path = f"{target_path}?{upstream.query}"

        conn: http.client.HTTPConnection | None = None
        try:
            if upstream.scheme == "https":
                conn = http.client.HTTPSConnection(
                    upstream.hostname,
                    upstream.port or 443,
                    timeout=15,
                    context=ssl.create_default_context(),
                )
            else:
                conn = http.client.HTTPConnection(
                    upstream.hostname,
                    upstream.port or 80,
                    timeout=15,
                )
            conn.request(self.command, target_path, body=body, headers=forward_headers)
            resp = conn.getresponse()
            resp_body = b"" if self.command == "HEAD" or resp.status == 304 else resp.read()

            self.send_response(resp.status, resp.reason)
            for key, value in resp.getheaders():
                lower = key.lower()
                if lower in HOP_BY_HOP_HEADERS or lower == "content-length":
                    continue
                self.send_header(key, value)
            if self.command != "HEAD" and resp.status != 304:
                self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            if resp_body:
                self.wfile.write(resp_body)
        except Exception:
            payload = (
                b'{"detail":"Nao foi possivel conectar ao servidor do GranMap."}'
            )
            self.send_response(HTTPStatus.BAD_GATEWAY)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
        finally:
            if conn is not None:
                conn.close()
        return True


def is_demo_server_running(host: str, port: int) -> bool:
    """Verifica se o servidor local do GranMap já está ativo na porta informada."""
    url = f"http://{host}:{port}/app/index.html"
    try:
        with urllib.request.urlopen(url, timeout=1.5) as response:
            return response.status == 200
    except Exception:
        return False


def find_app_browser() -> str | None:
    """Encontra Edge ou Chrome para abrir a demo em modo aplicativo."""
    candidates = [
        Path(os.environ.get("ProgramFiles(x86)", ""))
        / "Microsoft"
        / "Edge"
        / "Application"
        / "msedge.exe",
        Path(os.environ.get("ProgramFiles", ""))
        / "Microsoft"
        / "Edge"
        / "Application"
        / "msedge.exe",
        Path(os.environ.get("ProgramFiles", ""))
        / "Google"
        / "Chrome"
        / "Application"
        / "chrome.exe",
        Path(os.environ.get("LocalAppData", ""))
        / "Google"
        / "Chrome"
        / "Application"
        / "chrome.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return shutil.which("msedge") or shutil.which("chrome")


def open_demo_window(url: str, *, desktop: bool = False) -> None:
    """Abre o GranMap no navegador em janela dedicada (ou aba padrão)."""
    browser = find_app_browser()
    if browser:
        args = [browser, f"--app={url}"]
        if not desktop:
            args.append("--window-size=460,860")
        subprocess.Popen(args)
        return
    webbrowser.open(url)


def check_api_health(api_url: str) -> bool:
    """Verifica rapidamente se a API informada responde /health."""
    target = f"{api_url.rstrip('/')}/health"
    try:
        with urllib.request.urlopen(target, timeout=1.2) as response:
            return response.status == 200
    except Exception:
        return False


def ensure_local_backend(
    *, prefer_gateway: bool = True
) -> tuple[str, subprocess.Popen[bytes] | None]:
    """Usa granmap-pc (8787) se ativo; caso contrario sobe backend local (8100)."""
    if prefer_gateway and check_api_health(DEFAULT_API_URL):
        return DEFAULT_API_URL, None
    if check_api_health(LOCAL_API_URL):
        return LOCAL_API_URL, None

    venv_python = BACKEND_DIR / ".venv" / "Scripts" / "python.exe"
    python_exe = str(venv_python) if venv_python.is_file() else sys.executable
    demo_db = BACKEND_DIR / "granmap_demo.db"
    env = os.environ.copy()
    env["GRANMAP_DB_PATH"] = str(demo_db)
    if not demo_db.is_file():
        subprocess.run(
            [python_exe, str(BACKEND_DIR / "seed.py")],
            cwd=BACKEND_DIR,
            env=env,
            check=True,
        )

    proc = subprocess.Popen(
        [
            python_exe,
            "-m",
            "uvicorn",
            "main:app",
            "--host",
            "127.0.0.1",
            "--port",
            "8100",
        ],
        cwd=BACKEND_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("Backend local encerrou inesperadamente.")
        if check_api_health(LOCAL_API_URL):
            return LOCAL_API_URL, proc
        time.sleep(0.25)
    proc.terminate()
    raise RuntimeError("Backend local nao respondeu a tempo na porta 8100.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Abre o GranMap no PC para demonstração.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8088)
    parser.add_argument("--api-url", default=None)
    parser.add_argument(
        "--local",
        action="store_true",
        help="Conecta diretamente ao backend Python local http://127.0.0.1:8100.",
    )
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument(
        "--desktop",
        action="store_true",
        help="Abre sem largura fixa de celular.",
    )
    args = parser.parse_args(argv)

    if (
        not args.rebuild
        and not args.local
        and not args.api_url
        and not args.no_open
        and check_api_health(DEFAULT_API_URL)
    ):
        gateway_url = "http://127.0.0.1:8787/"
        print(f"GranMap PC ativo em {gateway_url}")
        open_demo_window(gateway_url, desktop=args.desktop)
        return 0

    register_mime_types()
    web_dir = ensure_web_build(rebuild=args.rebuild)
    demo_url = f"http://{args.host}:{args.port}/app/"

    if not args.rebuild and is_demo_server_running(args.host, args.port):
        print(f"GranMap já está rodando em {demo_url}")
        if not args.no_open:
            open_demo_window(demo_url, desktop=args.desktop)
        return 0

    backend_proc: subprocess.Popen[bytes] | None = None
    if args.api_url:
        api_url = args.api_url
    else:
        api_url, backend_proc = ensure_local_backend(prefer_gateway=not args.local)

    handler = partial(
        GranMapDemoHandler,
        directory=str(web_dir),
        api_url=api_url,
    )
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"GranMap PC pronto em {demo_url}")
    print(f"API conectada: {api_url}")
    print("Pressione Ctrl+C ou feche esta janela ao terminar a demonstração.")

    if not args.no_open:
        open_demo_window(demo_url, desktop=args.desktop)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrando GranMap PC...")
    finally:
        server.server_close()
        if backend_proc is not None and backend_proc.poll() is None:
            backend_proc.terminate()
            try:
                backend_proc.wait(timeout=3)
            except Exception:
                backend_proc.kill()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
