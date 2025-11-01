"""Tests for base_platform refactor - RED phase.

These tests verify that after renaming postgres -> base_platform:
1. New service exists at wizard/services/base_platform/
2. All imports work from wizard.services.base_platform
3. Service is registered as 'base_platform'
4. Spec files reference 'base_platform' service
5. Flow files reference 'base_platform' service
6. Migration action is first step in spec
"""

import pytest
import importlib
from pathlib import Path


class TestBaseplatformDirectoryStructure:
    """Test that base_platform directory exists with correct structure."""

    def test_base_platform_directory_exists(self):
        """After refactor, wizard/services/base_platform/ should exist."""
        base_platform_dir = Path('wizard/services/base_platform')
        assert base_platform_dir.exists(), "base_platform directory should exist"
        assert base_platform_dir.is_dir(), "base_platform should be a directory"

    def test_base_platform_has_required_files(self):
        """Base platform directory should have all required files."""
        base_platform_dir = Path('wizard/services/base_platform')
        required_files = [
            'spec.yaml',
            'teardown-spec.yaml',
            'actions.py',
            'validators.py',
            'discovery.py',
            'teardown_actions.py',
            '__init__.py'
        ]

        for filename in required_files:
            file_path = base_platform_dir / filename
            assert file_path.exists(), f"{filename} should exist in base_platform/"

    def test_base_platform_has_tests_directory(self):
        """Base platform should have tests directory."""
        tests_dir = Path('wizard/services/base_platform/tests')
        assert tests_dir.exists(), "tests directory should exist"
        assert tests_dir.is_dir(), "tests should be a directory"


class TestBaseplatformImports:
    """Test that imports work from wizard.services.base_platform."""

    def test_can_import_base_platform_actions(self):
        """Should be able to import actions from base_platform."""
        try:
            from wizard.services.base_platform import actions
            assert actions is not None
        except ImportError as e:
            pytest.fail(f"Failed to import base_platform.actions: {e}")

    def test_can_import_base_platform_validators(self):
        """Should be able to import validators from base_platform."""
        try:
            from wizard.services.base_platform import validators
            assert validators is not None
        except ImportError as e:
            pytest.fail(f"Failed to import base_platform.validators: {e}")

    def test_can_import_base_platform_discovery(self):
        """Should be able to import discovery from base_platform."""
        try:
            from wizard.services.base_platform import discovery
            assert discovery is not None
        except ImportError as e:
            pytest.fail(f"Failed to import base_platform.discovery: {e}")

    def test_can_import_base_platform_teardown_actions(self):
        """Should be able to import teardown_actions from base_platform."""
        try:
            from wizard.services.base_platform import teardown_actions
            assert teardown_actions is not None
        except ImportError as e:
            pytest.fail(f"Failed to import base_platform.teardown_actions: {e}")

    def test_migrate_legacy_postgres_config_exists(self):
        """Migration function should exist in base_platform.actions."""
        from wizard.services.base_platform.actions import migrate_legacy_postgres_config
        assert callable(migrate_legacy_postgres_config)


class TestBaseplatformServiceRegistration:
    """Test that base_platform is registered as a service."""

    def test_base_platform_in_services_init(self):
        """base_platform should be imported in wizard/services/__init__.py."""
        import wizard.services

        # Should be able to access base_platform module
        assert hasattr(wizard.services, 'base_platform'), \
            "base_platform should be registered in wizard.services"

    def test_base_platform_in_all_exports(self):
        """base_platform should be in __all__ exports."""
        import wizard.services

        assert hasattr(wizard.services, '__all__'), \
            "wizard.services should have __all__"
        assert 'base_platform' in wizard.services.__all__, \
            "base_platform should be in __all__"


class TestBaseplatformSpecFiles:
    """Test that spec files reference base_platform correctly."""

    def test_spec_yaml_has_base_platform_service_name(self):
        """spec.yaml should declare service as 'base_platform'."""
        import yaml

        spec_path = Path('wizard/services/base_platform/spec.yaml')
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        assert spec['service'] == 'base_platform', \
            "Service should be named 'base_platform' in spec.yaml"

    def test_spec_yaml_uses_base_platform_state_keys(self):
        """spec.yaml should use services.base_platform.postgres.* state keys."""
        import yaml

        spec_path = Path('wizard/services/base_platform/spec.yaml')
        with open(spec_path) as f:
            spec_content = f.read()

        # Should NOT have old postgres keys
        assert 'services.base_platform.postgres.' not in spec_content or \
               'services.base_platform.postgres.' in spec_content and 'migrate' in spec_content.lower(), \
            "spec.yaml should not use services.base_platform.postgres.* keys (except in migration docs)"

        # Should have new base_platform keys
        assert 'services.base_platform.postgres.' in spec_content, \
            "spec.yaml should use services.base_platform.postgres.* keys"

    def test_spec_yaml_has_migration_as_first_step(self):
        """spec.yaml should have migration action as first step."""
        import yaml

        spec_path = Path('wizard/services/base_platform/spec.yaml')
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        steps = spec.get('steps', [])
        assert len(steps) > 0, "spec.yaml should have steps"

        first_step = steps[0]
        assert first_step.get('id') == 'migrate_legacy_config', \
            "First step should be migrate_legacy_config"
        assert first_step.get('action') == 'base_platform.migrate_legacy_postgres_config', \
            "First step should call migration action"

    def test_teardown_spec_yaml_uses_base_platform_state_keys(self):
        """teardown-spec.yaml should use services.base_platform.postgres.* keys."""
        import yaml

        spec_path = Path('wizard/services/base_platform/teardown-spec.yaml')
        with open(spec_path) as f:
            spec_content = f.read()

        # Should have base_platform teardown keys
        assert 'services.base_platform.postgres.teardown.' in spec_content, \
            "teardown-spec.yaml should use services.base_platform.postgres.teardown.* keys"


class TestFlowFilesUpdated:
    """Test that flow files reference base_platform correctly."""

    def test_setup_yaml_references_base_platform(self):
        """setup.yaml should reference base_platform service."""
        import yaml

        setup_path = Path('wizard/flows/setup.yaml')
        with open(setup_path) as f:
            setup = yaml.safe_load(f)

        # Find base_platform in targets
        targets = setup.get('targets', [])
        base_platform_target = None
        for target in targets:
            if target.get('service') == 'base_platform':
                base_platform_target = target
                break

        assert base_platform_target is not None, \
            "setup.yaml should have base_platform in targets"

    def test_setup_yaml_dependencies_use_base_platform(self):
        """Other services should depend on base_platform, not postgres."""
        import yaml

        setup_path = Path('wizard/flows/setup.yaml')
        with open(setup_path) as f:
            setup = yaml.safe_load(f)

        targets = setup.get('targets', [])
        for target in targets:
            depends_on = target.get('depends_on', [])
            assert 'postgres' not in depends_on, \
                f"Service {target.get('service')} should not depend on 'postgres'"

    def test_clean_slate_yaml_references_base_platform(self):
        """clean-slate.yaml should reference base_platform."""
        import yaml

        clean_slate_path = Path('wizard/flows/clean-slate.yaml')
        with open(clean_slate_path) as f:
            clean_slate_content = f.read()

        # Should reference base_platform
        assert 'base_platform' in clean_slate_content, \
            "clean-slate.yaml should reference base_platform"

        # Should not reference postgres (except in legacy migration context)
        clean_slate = yaml.safe_load(open(clean_slate_path))
        targets = clean_slate.get('targets', [])
        for target in targets:
            assert target.get('service') != 'postgres', \
                "clean-slate.yaml should not have postgres as a service"


class TestOldPostgresServiceRemoved:
    """Test that old postgres service directory is removed."""

    def test_postgres_service_directory_does_not_exist(self):
        """Old wizard/services/postgres/ directory should not exist."""
        postgres_dir = Path('wizard/services/postgres')
        assert not postgres_dir.exists(), \
            "Old postgres directory should be removed after refactor"
