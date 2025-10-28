"""Integration tests for corporate registry images in the setup wizard."""

import pytest
from wizard.engine.runner import TestActionRunner
from wizard.engine.engine import WizardEngine
from wizard.engine.spec_loader import SpecLoader
from wizard.services import postgres, openmetadata, kerberos, pagila


class TestCorporateImageIntegration:
    """End-to-end tests for corporate Docker registry support."""

    @pytest.fixture
    def engine(self):
        """Create engine with test runner."""
        runner = TestActionRunner()
        engine = WizardEngine(runner)

        # Register validators and actions
        engine.validators['postgres.validate_image_url'] = postgres.validate_image_url
        engine.validators['postgres.validate_port'] = postgres.validate_port
        engine.actions['postgres.save_config'] = postgres.save_config
        engine.actions['postgres.pull_image'] = postgres.pull_image
        engine.actions['postgres.start_service'] = postgres.start_service

        engine.validators['kerberos.validate_domain'] = kerberos.validate_domain
        engine.validators['kerberos.validate_image_url'] = kerberos.validate_image_url
        engine.actions['kerberos.test_kerberos'] = kerberos.test_kerberos
        engine.actions['kerberos.save_config'] = kerberos.save_config
        engine.actions['kerberos.start_service'] = kerberos.start_service

        return engine

    def test_setup_with_jfrog_postgres_image(self, engine):
        """Should complete setup with JFrog corporate PostgreSQL image."""
        # Simulate user inputs for corporate setup
        headless_inputs = {
            'platform_name': 'corporate-test',
            'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01',
            'postgres_prebuilt': False,
            'postgres_auth': True,
            'postgres_password': 'TestPass123',
            'postgres_port': 5432,
        }

        # Execute the flow
        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify the corporate image was accepted and saved
        assert engine.state.get('services.postgres.image') == \
            'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01'

        # Check that save_config was called with the corporate image
        runner = engine.runner
        save_calls = [c for c in runner.calls if c[0] == 'save_config']
        assert len(save_calls) > 0

        config = save_calls[0][1]  # First argument to save_config
        assert config['services']['postgres']['image'] == \
            'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01'

    def test_setup_with_registry_port_number(self, engine):
        """Should handle registry URLs with port numbers."""
        headless_inputs = {
            'platform_name': 'port-test',
            'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': 'internal.artifactory.company.com:8443/docker-prod/postgres/17.5:v2025.10-hardened',
            'postgres_prebuilt': False,
            'postgres_auth': False,
            'postgres_port': 5432,
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        assert engine.state.get('services.postgres.image') == \
            'internal.artifactory.company.com:8443/docker-prod/postgres/17.5:v2025.10-hardened'

    def test_setup_with_corporate_kerberos_prebuilt(self, engine):
        """Should configure Kerberos with corporate prebuilt image."""
        headless_inputs = {
            'platform_name': 'kerberos-test',
            'select_openmetadata': False,
            'select_kerberos': True,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',  # Use default for postgres
            'postgres_prebuilt': False,
            'postgres_auth': False,
            'postgres_port': 5432,
            'kerberos_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest',
            'kerberos_mode': 'prebuilt',
            'kerberos_realm': 'CORP.EXAMPLE.COM',
            'kerberos_kdc': 'kdc.corp.example.com',
            'kerberos_admin_server': 'kadmin.corp.example.com',
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify Kerberos configured with corporate image
        assert engine.state.get('services.kerberos.image') == \
            'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest'
        assert engine.state.get('services.kerberos.mode') == 'prebuilt'

    def test_multi_service_corporate_images(self, engine):
        """Should handle multiple services with corporate images."""
        # Register OpenMetadata validators/actions
        engine.validators['openmetadata.validate_image_url'] = openmetadata.validate_image_url
        engine.validators['openmetadata.validate_port'] = openmetadata.validate_port
        engine.actions['openmetadata.save_config'] = openmetadata.save_config
        engine.actions['openmetadata.start_service'] = openmetadata.start_service

        headless_inputs = {
            'platform_name': 'multi-service-test',
            'select_openmetadata': True,
            'select_kerberos': True,
            'select_pagila': False,
            # PostgreSQL with corporate image
            'postgres_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/postgres/17.5:2025.10.01',
            'postgres_prebuilt': False,
            'postgres_auth': True,
            'postgres_password': 'TestPass123',
            'postgres_port': 5432,
            # OpenMetadata with corporate image
            'openmetadata_server_image': 'artifactory.corp.net/docker-public/openmetadata/server:1.5.11-approved',
            'openmetadata_ingestion_image': 'artifactory.corp.net/docker-public/openmetadata/ingestion:1.5.11-approved',
            'opensearch_image': 'docker-registry.internal.company.com/data/opensearch:2.18.0-enterprise',
            'openmetadata_port': 8585,
            # Kerberos with corporate prebuilt
            'kerberos_image': 'mycorp.jfrog.io/docker-mirror/mycorp-approved-images/kerberos-base:latest',
            'kerberos_mode': 'prebuilt',
            'kerberos_realm': 'CORP.EXAMPLE.COM',
            'kerberos_kdc': 'kdc.corp.example.com',
            'kerberos_admin_server': 'kadmin.corp.example.com',
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify all corporate images were accepted
        assert 'mycorp.jfrog.io' in engine.state.get('services.postgres.image', '')
        assert 'artifactory.corp.net' in engine.state.get('services.openmetadata.server_image', '')
        assert 'docker-registry.internal.company.com' in engine.state.get('services.openmetadata.opensearch_image', '')
        assert 'mycorp.jfrog.io' in engine.state.get('services.kerberos.image', '')

    def test_rejects_malformed_corporate_path(self, engine):
        """Should reject malformed corporate registry paths."""
        headless_inputs = {
            'platform_name': 'malformed-test',
            'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': '"mycorp.jfrog.io/postgres:17.5"',  # With quotes - common error
            'postgres_prebuilt': False,
            'postgres_auth': False,
            'postgres_port': 5432,
        }

        with pytest.raises(ValueError, match="Invalid image URL format"):
            engine.execute_flow('setup', headless_inputs=headless_inputs)

    def test_aws_ecr_image_format(self, engine):
        """Should accept AWS ECR format with account ID and region."""
        headless_inputs = {
            'platform_name': 'aws-test',
            'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': '123456789012.dkr.ecr.us-west-2.amazonaws.com/postgres:17.5',
            'postgres_prebuilt': False,
            'postgres_auth': False,
            'postgres_port': 5432,
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        assert '123456789012.dkr.ecr.us-west-2.amazonaws.com' in \
            engine.state.get('services.postgres.image', '')