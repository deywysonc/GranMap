from collections import defaultdict, deque
from contextlib import suppress
from time import monotonic

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from auth_router import CSRF_COOKIE, SESSION_COOKIE
from settings import Settings


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


def _client_key(request: Request, settings: Settings) -> str:
    if settings.trusted_proxy_headers:
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",", 1)[0].strip()
    return request.client.host if request.client else "unknown"


def install_http_middleware(app: FastAPI, settings: Settings) -> None:
    limiter = LoginRateLimiter(settings.login_attempts_per_minute)

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
        bearer_supplied = bool(request.headers.get("authorization"))
        session_cookie = request.cookies.get(SESSION_COOKIE)

        if path in {"/auth/login", "/auth/web-login"}:
            if not limiter.allow(_client_key(request, settings)):
                return JSONResponse(
                    status_code=429,
                    content={
                        "detail": "Muitas tentativas. Aguarde um minuto e tente novamente."
                    },
                    headers={"Retry-After": "60"},
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

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        if settings.cookie_secure:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains"
            )
        return response
