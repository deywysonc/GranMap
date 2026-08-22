from collections import defaultdict, deque
from contextlib import suppress
import hashlib
import json
import logging
import re
import secrets
from time import monotonic, time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from auth_router import CSRF_COOKIE, SESSION_COOKIE
from db import connect
from settings import Settings


LOGGER = logging.getLogger("granmap.http")
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{8,96}$")


REQUESTS = Counter(
    "granmap_http_requests_total",
    "Quantidade de requisições HTTP",
    ("method", "path", "status"),
)
LATENCY = Histogram(
    "granmap_http_request_duration_seconds",
    "Latência das requisições HTTP",
    ("method", "path"),
)


class LoginRateLimiter:
    def __init__(self, attempts_per_minute: int):
        self._limit = attempts_per_minute
        self._attempts: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = monotonic()
        window = now - 60
        entries = self._attempts[key]
        while entries and entries[0] < window:
            entries.popleft()
        if len(entries) >= self._limit:
            return False
        entries.append(now)
        return True


class DistributedLoginRateLimiter:
    """Compartilha o limite entre instâncias usando o banco da aplicação."""

    def __init__(self, attempts_per_minute: int):
        self._limit = attempts_per_minute
        self._fallback = LoginRateLimiter(attempts_per_minute)

    def allow(self, key: str) -> bool:
        bucket = int(time() // 60)
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        bucket_key = f"login:{digest}"
        try:
            with connect() as con:
                row = con.execute(
                    "SELECT window_start, attempts FROM rate_limit_buckets WHERE key = ?",
                    (bucket_key,),
                ).fetchone()
                if row is None or int(row["window_start"]) != bucket:
                    con.execute(
                        """
                        INSERT INTO rate_limit_buckets(key, window_start, attempts)
                        VALUES (?, ?, 1)
                        ON CONFLICT(key) DO UPDATE SET
                            window_start = excluded.window_start,
                            attempts = 1,
                            updated_at = CURRENT_TIMESTAMP
                        """,
                        (bucket_key, bucket),
                    )
                    allowed = True
                elif int(row["attempts"]) >= self._limit:
                    allowed = False
                else:
                    con.execute(
                        """
                        UPDATE rate_limit_buckets
                        SET attempts = attempts + 1, updated_at = CURRENT_TIMESTAMP
                        WHERE key = ?
                        """,
                        (bucket_key,),
                    )
                    allowed = True
                con.execute(
                    "DELETE FROM rate_limit_buckets WHERE window_start < ?",
                    (bucket - 5,),
                )
                con.commit()
                return allowed
        except Exception:
            LOGGER.exception("distributed_rate_limit_unavailable")
            return self._fallback.allow(key)


def _client_key(request: Request, settings: Settings) -> str:
    if settings.trusted_proxy_headers:
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client else "unknown"


def install_http_middleware(app: FastAPI, settings: Settings) -> None:
    limiter = DistributedLoginRateLimiter(settings.login_attempts_per_minute)

    @app.get("/metrics", include_in_schema=False)
    def metrics():
        if not settings.metrics_enabled:
            return Response(status_code=404)
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.middleware("http")
    async def security_and_observability(request: Request, call_next):
        started = monotonic()
        path = request.url.path
        method = request.method.upper()
        supplied_request_id = request.headers.get("x-request-id", "")
        request_id = (
            supplied_request_id
            if REQUEST_ID_PATTERN.fullmatch(supplied_request_id)
            else f"gm-{secrets.token_hex(12)}"
        )
        bearer_supplied = bool(request.headers.get("authorization"))
        session_cookie = request.cookies.get(SESSION_COOKIE)

        if path in {
            "/auth/login",
            "/auth/web-login",
            "/auth/password-reset/request",
        }:
            if not limiter.allow(_client_key(request, settings)):
                return JSONResponse(
                    status_code=429,
                    content={
                        "detail": "Muitas tentativas. Aguarde um minuto e tente novamente."
                    },
                    headers={"Retry-After": "60", "X-Request-ID": request_id},
                )

        if session_cookie and not bearer_supplied:
            headers = list(request.scope.get("headers", []))
            headers.append(
                (b"authorization", f"Bearer {session_cookie}".encode("utf-8"))
            )
            request.scope["headers"] = headers

        unsafe = method not in {"GET", "HEAD", "OPTIONS", "TRACE"}
        if (
            unsafe
            and session_cookie
            and not bearer_supplied
            and path != "/auth/web-login"
        ):
            csrf_cookie = request.cookies.get(CSRF_COOKIE, "")
            csrf_header = request.headers.get("x-csrf-token", "")
            if not csrf_cookie or csrf_header != csrf_cookie:
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Proteção CSRF inválida."},
                    headers={"X-Request-ID": request_id},
                )

        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
        finally:
            elapsed = monotonic() - started
            if settings.metrics_enabled:
                normalized = request.scope.get("route")
                route_path = getattr(normalized, "path", path)
                with suppress(Exception):
                    REQUESTS.labels(method, route_path, str(status)).inc()
                    LATENCY.labels(method, route_path).observe(elapsed)
            LOGGER.info(
                json.dumps(
                    {
                        "event": "http.request",
                        "request_id": request_id,
                        "method": method,
                        "path": path,
                        "status": status,
                        "duration_ms": round(elapsed * 1000, 2),
                    },
                    ensure_ascii=False,
                )
            )

        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        if settings.cookie_secure:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response
