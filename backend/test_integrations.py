import unittest

import integration_router
from settings import Settings


class IntegrationReadinessTest(unittest.TestCase):
    def test_public_status_never_exposes_credentials(self):
        payload = integration_router.integration_status()
        self.assertIn("checks", payload)
        self.assertIn("missing", payload)
        self.assertNotIn("erp_api_token", payload)
        self.assertNotIn("sso_issuer_url", payload)

    def test_commercial_launch_fails_closed_without_external_inputs(self):
        settings = Settings(
            environment="production",
            database_url="postgresql://granmap:test@database/granmap",
            cookie_secure=True,
            public_origins=["https://admin.granmap.example"],
            commercial_launch=True,
        )
        with self.assertRaisesRegex(RuntimeError, "Lançamento comercial bloqueado"):
            settings.validate_production()

    def test_commercial_launch_accepts_complete_configuration(self):
        settings = Settings(
            environment="production",
            database_url="postgresql://granmap:test@database/granmap",
            cookie_secure=True,
            public_origins=["https://admin.granmap.example"],
            commercial_launch=True,
            institutional_map_approved=True,
            field_calibration_completed=True,
            sso_issuer_url="https://idp.granmap.example",
            sso_client_id="granmap",
            erp_base_url="https://erp.granmap.example",
            erp_api_token="secret",
            push_provider="fcm",
            push_credentials_configured=True,
        )
        settings.validate_production()


if __name__ == "__main__":
    unittest.main()
