from fastapi import APIRouter, Header

from auth_router import require_roles
from settings import get_settings


router = APIRouter(prefix="/integrations", tags=["Integrações institucionais"])
ADMIN_ROLES = {"coordination", "admin"}


def _status_payload():
    settings = get_settings()
    checks = {
        "mapa_institucional": settings.institutional_map_approved,
        "calibracao_indoor": settings.field_calibration_completed,
        "sso": bool(settings.sso_issuer_url and settings.sso_client_id),
        "erp_academico": bool(settings.erp_base_url and settings.erp_api_token),
        "push": bool(settings.push_provider and settings.push_credentials_configured),
    }
    missing = [key for key, configured in checks.items() if not configured]
    return {
        "environment": settings.environment,
        "commercial_launch": settings.commercial_launch,
        "ready": not missing,
        "checks": checks,
        "missing": missing,
        "message": (
            "Integrações e validações comerciais concluídas."
            if not missing
            else "A demo continua funcional; o lançamento comercial aguarda dependências externas."
        ),
    }


@router.get("/status")
def integration_status():
    """Resumo público sem URLs, tokens ou outros segredos."""
    return _status_payload()


@router.get("/readiness")
def integration_readiness(
    authorization: str | None = Header(default=None),
):
    require_roles(authorization, ADMIN_ROLES)
    return _status_payload()
