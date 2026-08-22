from functools import lru_cache
from pathlib import Path
from typing import Annotated

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    """Configuração operacional, sempre proveniente do ambiente em produção."""

    model_config = SettingsConfigDict(
        env_prefix="GRANMAP_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = "development"
    database_url: str | None = None
    db_path: Path = Path(__file__).with_name("granmap.db")
    # Evita que pydantic-settings tente decodificar a variável como JSON antes
    # do nosso validador. Em produção aceitamos a forma operacional simples:
    # GRANMAP_PUBLIC_ORIGINS=https://admin.example.com,https://app.example.com
    public_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)
    cookie_secure: bool = False
    session_days: int = Field(default=30, ge=1, le=90)
    login_attempts_per_minute: int = Field(default=8, ge=3, le=100)
    trusted_proxy_headers: bool = False
    metrics_enabled: bool = True
    commercial_launch: bool = False
    institutional_map_approved: bool = False
    field_calibration_completed: bool = False
    sso_issuer_url: str | None = None
    sso_client_id: str | None = None
    erp_base_url: str | None = None
    erp_api_token: str | None = None
    push_provider: str | None = None
    push_credentials_configured: bool = False

    @field_validator("public_origins", mode="before")
    @classmethod
    def parse_origins(cls, value):
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    def validate_production(self) -> None:
        if not self.is_production:
            return
        if not self.database_url or not self.database_url.startswith(
            ("postgresql://", "postgresql+psycopg://")
        ):
            raise RuntimeError(
                "Produção exige GRANMAP_DATABASE_URL apontando para PostgreSQL."
            )
        if not self.cookie_secure:
            raise RuntimeError("Produção exige GRANMAP_COOKIE_SECURE=true.")
        if not self.public_origins:
            raise RuntimeError("Produção exige GRANMAP_PUBLIC_ORIGINS.")
        if self.commercial_launch:
            missing = []
            if not self.institutional_map_approved:
                missing.append("GRANMAP_INSTITUTIONAL_MAP_APPROVED")
            if not self.field_calibration_completed:
                missing.append("GRANMAP_FIELD_CALIBRATION_COMPLETED")
            if not self.sso_issuer_url or not self.sso_client_id:
                missing.append("GRANMAP_SSO_ISSUER_URL/GRANMAP_SSO_CLIENT_ID")
            if not self.erp_base_url or not self.erp_api_token:
                missing.append("GRANMAP_ERP_BASE_URL/GRANMAP_ERP_API_TOKEN")
            if not self.push_provider or not self.push_credentials_configured:
                missing.append("GRANMAP_PUSH_PROVIDER/GRANMAP_PUSH_CREDENTIALS_CONFIGURED")
            if missing:
                raise RuntimeError(
                    "Lançamento comercial bloqueado; configure: " + ", ".join(missing)
                )


@lru_cache
def get_settings() -> Settings:
    return Settings()
