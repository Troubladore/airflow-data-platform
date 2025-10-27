"""Tests for setup flow composition - RED phase.

This test suite validates the orchestration of multiple services through
the setup flow. The setup flow coordinates service selection and execution
while respecting dependencies.

Test philosophy:
- Test flow orchestration, not individual service logic
- Use MockActionRunner for all side effects
- Use headless_inputs for non-interactive testing
- Validate state transitions and action ordering
"""

import pytest
from pathlib import Path
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner
from wizard.engine.loader import SpecLoader


class TestSetupFlowLoads:
    """Tests for setup flow file existence and basic loading."""

    def test_setup_flow_yaml_exists(self):
        """Should have flows/setup.yaml file."""
        flow_path = Path(__file__).parent.parent / "flows" / "setup.yaml"
        assert flow_path.exists(), "flows/setup.yaml must exist"

    def test_setup_flow_loads_successfully(self):
        """Should load setup.yaml without validation errors."""
        loader = SpecLoader(base_path=Path(__file__).parent.parent)
        flow = loader.load_flow("setup")

        assert flow is not None, "setup flow should load"
        assert flow.name == "setup", "flow name should be 'setup'"


class TestSetupFlowStructure:
    """Tests for setup flow structure and required fields."""

    @pytest.fixture
    def loader(self):
        """Create SpecLoader for testing."""
        return SpecLoader(base_path=Path(__file__).parent.parent)

    def test_setup_flow_has_version(self, loader):
        """Should have version field."""
        flow = loader.load_flow("setup")
        assert hasattr(flow, 'version'), "flow must have version field"
        assert flow.version is not None, "version should not be None"

    def test_setup_flow_has_description(self, loader):
        """Should have description field."""
        flow = loader.load_flow("setup")
        assert hasattr(flow, 'description'), "flow must have description field"
        assert len(flow.description) > 0, "description should not be empty"

    def test_setup_flow_has_service_selection(self, loader):
        """Should have service_selection steps."""
        flow = loader.load_flow("setup")
        assert hasattr(flow, 'service_selection'), "flow must have service_selection"
        assert isinstance(flow.service_selection, list), "service_selection should be a list"
        assert len(flow.service_selection) > 0, "service_selection should not be empty"

    def test_setup_flow_has_targets(self, loader):
        """Should have targets list."""
        flow = loader.load_flow("setup")
        assert hasattr(flow, 'targets'), "flow must have targets"
        assert isinstance(flow.targets, list), "targets should be a list"
        assert len(flow.targets) >= 4, "should have at least 4 services (postgres, openmetadata, kerberos, pagila)"


class TestServiceSelectionStep:
    """Tests for service selection logic in setup flow."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)

        # Register service validators and actions
        self._register_services(engine)

        return engine

    def _register_services(self, engine):
        """Register all service modules with engine."""
        from wizard.services import postgres, openmetadata, kerberos, pagila

        # Register postgres
        engine.validators['postgres.validate_image_url'] = postgres.validate_image_url
        engine.validators['postgres.validate_port'] = postgres.validate_port
        engine.actions['postgres.save_config'] = postgres.save_config
        engine.actions['postgres.start_service'] = postgres.start_service

        # Register openmetadata
        engine.validators['openmetadata.validate_image_url'] = openmetadata.validate_image_url
        engine.validators['openmetadata.validate_port'] = openmetadata.validate_port
        engine.actions['openmetadata.save_config'] = openmetadata.save_config
        engine.actions['openmetadata.start_service'] = openmetadata.start_service

        # Register kerberos
        engine.validators['kerberos.validate_domain'] = kerberos.validate_domain
        engine.validators['kerberos.validate_image_url'] = kerberos.validate_image_url
        engine.actions['kerberos.test_kerberos'] = kerberos.test_kerberos
        engine.actions['kerberos.save_config'] = kerberos.save_config

        # Register pagila
        engine.validators['pagila.validate_git_url'] = pagila.validate_git_url
        engine.actions['pagila.save_config'] = pagila.save_config
        engine.actions['pagila.install_pagila'] = pagila.install_pagila

    def test_service_selection_updates_state(self, engine):
        """Should update state with selected services."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': True,
            'select_pagila': False,  # Don't select pagila
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify state has service selections
        assert 'services.openmetadata.enabled' in engine.state
        assert engine.state['services.openmetadata.enabled'] is True

        assert 'services.kerberos.enabled' in engine.state
        assert engine.state['services.kerberos.enabled'] is True

        assert 'services.pagila.enabled' in engine.state
        assert engine.state['services.pagila.enabled'] is False

    def test_postgres_always_enabled(self, engine):
        """PostgreSQL should always be enabled regardless of selection."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,  # Select no optional services
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Postgres should be enabled even if not explicitly selected
        assert 'services.postgres.enabled' in engine.state
        assert engine.state['services.postgres.enabled'] is True


class TestServiceExecutionOrdering:
    """Tests for correct execution order based on dependencies."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_postgres_executes_before_openmetadata(self, engine):
        """PostgreSQL must execute before OpenMetadata (dependency)."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': False,
            # Postgres inputs
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'changeme',
            'postgres_port': 5432,
            # OpenMetadata inputs
            'server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
            'opensearch_image': 'opensearchproject/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': True
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Check action call order
        runner = engine.runner
        action_calls = [call for call in runner.calls if call[0] in ['save_config', 'run_shell']]

        # Find indices of postgres and openmetadata actions
        postgres_indices = [i for i, call in enumerate(action_calls)
                           if 'postgres' in str(call)]
        openmetadata_indices = [i for i, call in enumerate(action_calls)
                               if 'openmetadata' in str(call)]

        if postgres_indices and openmetadata_indices:
            assert max(postgres_indices) < min(openmetadata_indices), \
                "All postgres actions should complete before openmetadata actions"

    def test_postgres_executes_before_pagila(self, engine):
        """PostgreSQL must execute before Pagila (dependency)."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': True,
            # Postgres inputs
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'changeme',
            'postgres_port': 5432,
            # Pagila inputs
            'pagila_repo_url': 'https://github.com/devrimgunduz/pagila.git'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Check action call order
        runner = engine.runner
        action_calls = [call for call in runner.calls if call[0] in ['save_config', 'run_shell']]

        # Find indices of postgres and pagila actions
        # Use more specific matching: postgres service actions vs pagila service actions
        postgres_indices = [i for i, call in enumerate(action_calls)
                           if call[0] == 'save_config' and 'postgres' in str(call[1].get('services', {}).keys())]
        pagila_indices = [i for i, call in enumerate(action_calls)
                         if call[0] == 'save_config' and 'pagila' in str(call[1].get('services', {}).keys())]

        if postgres_indices and pagila_indices:
            assert max(postgres_indices) < min(pagila_indices), \
                "All postgres actions should complete before pagila actions"

    def test_kerberos_can_execute_independently(self, engine):
        """Kerberos has no dependencies and can execute in any order."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': True,
            'select_pagila': False,
            # Postgres inputs (always executed)
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432,
            # Kerberos inputs
            'domain_input': 'COMPANY.COM',
            'image_input': 'ubuntu:22.04'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Should execute without errors
        # Kerberos can run before or after postgres
        runner = engine.runner
        assert len(runner.calls) > 0, "Should have executed some actions"


class TestIntegrationScenarioAllDefaults:
    """Test Scenario 1: All defaults - just press Enter through everything."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_all_defaults_scenario(self, engine):
        """Should handle all default values (empty inputs)."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,  # No optional services
            # All postgres steps use defaults (empty strings trigger defaults)
            'postgres_image': '',
            'postgres_auth': '',  # Empty string will use default (True = require password)
            'postgres_password': '',  # Will use default 'changeme'
            'postgres_port': ''
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify default values were used
        assert engine.state.get('services.postgres.image') == 'postgres:17.5-alpine'
        assert engine.state.get('services.postgres.auth_method') == 'md5'
        assert engine.state.get('services.postgres.port') == 5432
        assert engine.state.get('services.postgres.prebuilt') is False

    def test_all_defaults_calls_postgres_actions(self, engine):
        """Should call postgres save, init, and start actions."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': '',
            'postgres_auth': '',
            'postgres_password': '',
            'postgres_port': ''
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        runner = engine.runner
        save_calls = [c for c in runner.calls if c[0] == 'save_config']
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']

        assert len(save_calls) >= 1, "Should call save_config at least once"
        assert len(shell_calls) >= 2, "Should call run_shell for init and start"


class TestIntegrationScenarioHybrid:
    """Test Scenario 2: Hybrid - some default images, some custom."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_hybrid_default_and_custom_images(self, engine):
        """Should handle mix of default and custom Docker images."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': False,
            # Postgres: use default image
            'postgres_image': '',  # Default
            'postgres_prebuilt': True,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'secret123',
            'postgres_port': 5432,
            # OpenMetadata: use custom image
            'server_image': 'myregistry.company.com/openmetadata:1.5.0-custom',
            'opensearch_image': 'myregistry.company.com/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': False
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify postgres used default
        assert engine.state.get('services.postgres.image') == 'postgres:17.5-alpine'
        assert engine.state.get('services.postgres.prebuilt') is True

        # Verify openmetadata used custom
        assert 'myregistry.company.com' in engine.state.get('services.openmetadata.server_image', '')
        assert engine.state.get('services.openmetadata.use_prebuilt') is False


class TestIntegrationScenarioAllCustom:
    """Test Scenario 3: All custom images."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_all_custom_images(self, engine):
        """Should handle all custom Docker images from corporate registry."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': True,
            'select_pagila': False,
            # All custom images from corporate registry
            'postgres_image': 'artifactory.company.com/postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': True,  # Boolean: require password (any auth method)
            'postgres_password': 'verysecure',
            'postgres_port': 5433,
            'server_image': 'artifactory.company.com/openmetadata/server:1.5.0',
            'opensearch_image': 'artifactory.company.com/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': False,
            'domain_input': 'EXAMPLE.COM',
            'image_input': 'artifactory.company.com/ubuntu:22.04'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify all images come from corporate registry
        assert 'artifactory.company.com' in engine.state.get('services.postgres.image', '')
        assert 'artifactory.company.com' in engine.state.get('services.openmetadata.server_image', '')
        assert 'artifactory.company.com' in engine.state.get('services.kerberos.image', '')

        # Verify all services enabled
        assert engine.state.get('services.openmetadata.enabled') is True
        assert engine.state.get('services.kerberos.enabled') is True


class TestIntegrationScenarioAllBuilt:
    """Test Scenario 4: All built (layering approach)."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_all_built_layering_approach(self, engine):
        """Should handle all services using build-from-source approach."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': True,
            'select_pagila': True,
            # All services: base images + build
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,  # Build approach
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'changeme',
            'postgres_port': 5432,
            'server_image': 'ubuntu:22.04',  # Base image
            'opensearch_image': 'ubuntu:22.04',  # Base image
            'port': 8585,
            'use_prebuilt': False,  # Build approach
            'domain_input': 'CORP.LOCAL',
            'image_input': 'ubuntu:22.04',  # Base image
            'pagila_repo_url': 'https://github.com/devrimgunduz/pagila.git'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify all services set to build (not prebuilt)
        assert engine.state.get('services.postgres.prebuilt') is False
        assert engine.state.get('services.openmetadata.use_prebuilt') is False

        # Verify all services enabled
        assert engine.state.get('services.openmetadata.enabled') is True
        assert engine.state.get('services.kerberos.enabled') is True
        assert engine.state.get('services.pagila.enabled') is True


class TestIntegrationScenarioMixBuiltPrebuilt:
    """Test Scenario 5: Mix of built and prebuilt."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_mix_of_built_and_prebuilt(self, engine):
        """Should handle some services prebuilt, others built."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': True,
            # Postgres: prebuilt
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'changeme',
            'postgres_port': 5432,
            # OpenMetadata: build from source
            'server_image': 'ubuntu:22.04',
            'opensearch_image': 'ubuntu:22.04',
            'port': 8585,
            'use_prebuilt': False,
            # Pagila: always built from repo
            'pagila_repo_url': 'https://github.com/devrimgunduz/pagila.git'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify mixed approach
        assert engine.state.get('services.postgres.prebuilt') is True
        assert engine.state.get('services.openmetadata.use_prebuilt') is False

        # Verify both services enabled
        assert engine.state.get('services.openmetadata.enabled') is True
        assert engine.state.get('services.pagila.enabled') is True


class TestIntegrationScenarioAllPrebuilt:
    """Test Scenario 6: All prebuilt (OOB ready)."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_all_prebuilt_out_of_box(self, engine):
        """Should handle all services using prebuilt images (fastest setup)."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': False,
            # All services: prebuilt ready-to-use images
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432,
            'server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
            'opensearch_image': 'opensearchproject/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': True
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify all services use prebuilt
        assert engine.state.get('services.postgres.prebuilt') is True
        assert engine.state.get('services.openmetadata.use_prebuilt') is True

        # Verify trust auth (no password needed)
        assert engine.state.get('services.postgres.auth_method') == 'trust'

    def test_all_prebuilt_minimal_prompts(self, engine):
        """Prebuilt scenario should skip build-related questions."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,  # Just postgres
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,  # Should skip build questions
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Should complete with minimal inputs
        runner = engine.runner
        assert len(runner.calls) > 0, "Should execute actions"

        # Verify prebuilt mode
        assert engine.state.get('services.postgres.prebuilt') is True


class TestConditionalServiceInclusion:
    """Tests for conditional execution based on service selection."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_disabled_services_not_executed(self, engine):
        """Services not selected should not execute their steps."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,  # Only postgres (always enabled)
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify disabled services not in state
        assert engine.state.get('services.openmetadata.enabled', False) is False
        assert engine.state.get('services.kerberos.enabled', False) is False
        assert engine.state.get('services.pagila.enabled', False) is False

        # Verify no actions called for disabled services
        runner = engine.runner
        action_calls_str = str(runner.calls)
        assert 'openmetadata' not in action_calls_str
        assert 'kerberos' not in action_calls_str
        assert 'pagila' not in action_calls_str

    def test_enabled_services_executed(self, engine):
        """Services selected should execute all their steps."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': True,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432,
            'domain_input': 'EXAMPLE.COM',
            'image_input': 'ubuntu:22.04'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify kerberos is enabled and executed
        assert engine.state.get('services.kerberos.enabled') is True
        assert engine.state.get('services.kerberos.domain') == 'EXAMPLE.COM'
        assert engine.state.get('services.kerberos.image') == 'ubuntu:22.04'

        # Verify kerberos actions were called
        runner = engine.runner
        action_calls_str = str(runner.calls)
        assert 'kerberos' in action_calls_str or len(runner.calls) > 3  # Postgres + Kerberos actions


class TestFlowStateManagement:
    """Tests for state management across flow execution."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_state_persists_across_services(self, engine):
        """State should persist across service executions."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'secret',
            'postgres_port': 5432,
            'server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
            'opensearch_image': 'opensearchproject/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': True
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify both postgres and openmetadata state exists
        assert 'services.postgres.image' in engine.state
        assert 'services.openmetadata.server_image' in engine.state

        # State from postgres should still be available when openmetadata runs
        assert engine.state['services.postgres.password'] == 'secret'

    def test_state_namespaced_by_service(self, engine):
        """Each service's state should be namespaced correctly."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': True,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432,
            'domain_input': 'CORP.LOCAL',
            'image_input': 'ubuntu:22.04'
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        # Verify namespace separation
        assert 'services.postgres.image' in engine.state
        assert 'services.kerberos.domain' in engine.state

        # Verify no namespace collision
        assert engine.state['services.postgres.image'] == 'postgres:17.5-alpine'
        assert engine.state['services.kerberos.image'] == 'ubuntu:22.04'


class TestActionRunnerIntegration:
    """Tests for MockActionRunner recording of actions."""

    @pytest.fixture
    def engine(self):
        """Create WizardEngine with MockActionRunner."""
        runner = MockActionRunner()
        base_path = Path(__file__).parent.parent
        engine = WizardEngine(runner=runner, base_path=base_path)
        return engine

    def test_runner_records_all_save_config_calls(self, engine):
        """Should record all save_config calls to runner."""
        headless_inputs = {
                        'select_openmetadata': True,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': True,
            'postgres_auth': False,  # Boolean: no password (trust auth)
            'postgres_port': 5432,
            'server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
            'opensearch_image': 'opensearchproject/opensearch:2.9.0',
            'port': 8585,
            'use_prebuilt': True
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        runner = engine.runner
        save_calls = [c for c in runner.calls if c[0] == 'save_config']

        # Should have save_config calls for postgres and openmetadata
        assert len(save_calls) >= 2, "Should save config for multiple services"

    def test_runner_records_shell_commands_in_order(self, engine):
        """Should record shell commands in correct execution order."""
        headless_inputs = {
                        'select_openmetadata': False,
            'select_kerberos': False,
            'select_pagila': False,
            'postgres_image': 'postgres:17.5-alpine',
            'postgres_prebuilt': False,
            'postgres_auth': True,  # Boolean: require password
            'postgres_password': 'changeme',
            'postgres_port': 5432
        }

        engine.execute_flow('setup', headless_inputs=headless_inputs)

        runner = engine.runner
        shell_calls = [c for c in runner.calls if c[0] == 'run_shell']

        # Should have shell call for start (init happens automatically via docker-entrypoint-initdb.d)
        assert len(shell_calls) >= 1, "Should have start command"

        # Verify start command is called
        start_call = None
        for call in shell_calls:
            if 'start' in str(call):
                start_call = call
                break

        assert start_call is not None, "Should call 'make start' command"

        # Verify init-db is NOT called (it's vestigial - PostgreSQL auto-initializes)
        init_calls = [c for c in shell_calls if 'init-db' in str(c)]
        assert len(init_calls) == 0, "Should NOT call init-db (database auto-initializes)"
