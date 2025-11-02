"""Tests for base_platform setup flow ordering and output - RED phase.

These tests verify:
1. Test containers are configured BEFORE platform postgres starts
2. Section headers are displayed at appropriate points
3. Output has proper visual separation with newlines
"""

import pytest
import yaml
from pathlib import Path


class TestNetworkCreation:
    """Tests that platform_network is created first."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_has_create_network_action(self, spec):
        """Should have create_platform_network action step."""
        steps = {s['id']: s for s in spec['steps']}

        assert 'create_platform_network' in steps, \
            "Should have create_platform_network step"

        network_step = steps['create_platform_network']
        assert network_step['type'] == 'action', \
            "create_platform_network should be an action step"
        assert network_step['action'] == 'base_platform.create_platform_network', \
            "Should use base_platform.create_platform_network action"

    def test_create_network_is_first_step_after_migration(self, spec):
        """create_platform_network should be first step after legacy migration."""
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        migrate_idx = step_ids.index('migrate_legacy_config')
        network_idx = step_ids.index('create_platform_network')

        assert network_idx == migrate_idx + 1, \
            "create_platform_network should be immediately after migrate_legacy_config"

    def test_create_network_action_exists(self):
        """Should have create_platform_network action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'create_platform_network'), \
            "actions.py should have create_platform_network function"


class TestSpecStepOrdering:
    """Tests for correct ordering of setup steps."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_test_containers_configured_before_postgres_starts(self, spec):
        """Test containers (postgres-test, sqlcmd-test) should be configured BEFORE postgres_start.

        This ensures the connectivity test containers are built and ready before we try
        to start the platform postgres database.
        """
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        # Find positions
        postgres_start_idx = step_ids.index('postgres_start')
        postgres_test_prebuilt_idx = step_ids.index('postgres_test_prebuilt')
        sqlcmd_test_prebuilt_idx = step_ids.index('sqlcmd_test_prebuilt')

        # Test containers should come BEFORE postgres_start
        assert postgres_test_prebuilt_idx < postgres_start_idx, \
            "postgres_test_prebuilt should come before postgres_start"
        assert sqlcmd_test_prebuilt_idx < postgres_start_idx, \
            "sqlcmd_test_prebuilt should come before postgres_start"


class TestSpecSectionHeaders:
    """Tests for section header display actions."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_has_base_platform_section_header(self, spec):
        """Should display 'Base Platform Configuration' section header after service selection.

        This header appears after the Pagila Y/n question to clearly indicate
        we're entering the base platform configuration phase.
        """
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        # Should have a display_base_platform_header action before postgres_image
        assert 'display_base_platform_header' in step_ids, \
            "Should have display_base_platform_header action"

        # Header should come before postgres_image question
        header_idx = step_ids.index('display_base_platform_header')
        postgres_image_idx = step_ids.index('postgres_image')
        assert header_idx < postgres_image_idx, \
            "Base platform header should come before postgres_image"

    def test_has_test_containers_section_header(self, spec):
        """Should display 'Connectivity Test Containers' subsection header.

        This subsection header appears before configuring postgres-test and sqlcmd-test
        to clearly show we're setting up test containers.
        """
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        # Should have a display_test_containers_header action
        assert 'display_test_containers_header' in step_ids, \
            "Should have display_test_containers_header action"

        # Header should come before postgres_test_prebuilt
        header_idx = step_ids.index('display_test_containers_header')
        postgres_test_idx = step_ids.index('postgres_test_prebuilt')
        assert header_idx < postgres_test_idx, \
            "Test containers header should come before postgres_test_prebuilt"

    def test_has_platform_database_section_header(self, spec):
        """Should display 'Platform PostgreSQL Database' subsection header.

        This subsection header appears before starting the platform postgres database
        to clearly show we're setting up the main database.
        """
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        # Should have a display_platform_database_header action
        assert 'display_platform_database_header' in step_ids, \
            "Should have display_platform_database_header action"

        # Header should come before postgres_start
        header_idx = step_ids.index('display_platform_database_header')
        postgres_start_idx = step_ids.index('postgres_start')
        assert header_idx < postgres_start_idx, \
            "Platform database header should come before postgres_start"


class TestActionsImplemented:
    """Tests that header display actions are implemented."""

    def test_display_base_platform_header_action_exists(self):
        """Should have display_base_platform_header action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'display_base_platform_header'), \
            "actions.py should have display_base_platform_header function"

    def test_display_test_containers_header_action_exists(self):
        """Should have display_test_containers_header action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'display_test_containers_header'), \
            "actions.py should have display_test_containers_header function"

    def test_display_platform_database_header_action_exists(self):
        """Should have display_platform_database_header action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'display_platform_database_header'), \
            "actions.py should have display_platform_database_header function"


class TestTestContainersBuildStep:
    """Tests that test containers are actually built."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_has_build_test_containers_action(self, spec):
        """Should have build_test_containers action step."""
        steps = {s['id']: s for s in spec['steps']}

        assert 'build_test_containers' in steps, \
            "Should have build_test_containers step"

        build_step = steps['build_test_containers']
        assert build_step['type'] == 'action', \
            "build_test_containers should be an action step"
        assert build_step['action'] == 'base_platform.build_test_containers', \
            "Should use base_platform.build_test_containers action"

    def test_build_test_containers_comes_after_save_test_config(self, spec):
        """build_test_containers should come after save_test_config."""
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        save_idx = step_ids.index('save_test_config')
        build_idx = step_ids.index('build_test_containers')

        assert build_idx > save_idx, \
            "build_test_containers should come after save_test_config"

    def test_build_test_containers_comes_before_platform_database_header(self, spec):
        """build_test_containers should come before platform postgres starts."""
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        build_idx = step_ids.index('build_test_containers')
        header_idx = step_ids.index('display_platform_database_header')

        assert build_idx < header_idx, \
            "build_test_containers should come before display_platform_database_header"

    def test_build_test_containers_action_exists(self):
        """Should have build_test_containers action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'build_test_containers'), \
            "actions.py should have build_test_containers function"


class TestTestContainersStartStep:
    """Tests that test containers are started as running containers."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_has_start_test_containers_action(self, spec):
        """Should have start_test_containers action step."""
        steps = {s['id']: s for s in spec['steps']}

        assert 'start_test_containers' in steps, \
            "Should have start_test_containers step"

        start_step = steps['start_test_containers']
        assert start_step['type'] == 'action', \
            "start_test_containers should be an action step"
        assert start_step['action'] == 'base_platform.start_test_containers', \
            "Should use base_platform.start_test_containers action"

    def test_start_test_containers_comes_after_build(self, spec):
        """start_test_containers should come after build_test_containers."""
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        build_idx = step_ids.index('build_test_containers')
        start_idx = step_ids.index('start_test_containers')

        assert start_idx > build_idx, \
            "start_test_containers should come after build_test_containers"

    def test_start_test_containers_comes_before_platform_database_header(self, spec):
        """start_test_containers should come before platform postgres starts."""
        steps = spec['steps']
        step_ids = [s['id'] for s in steps]

        start_idx = step_ids.index('start_test_containers')
        header_idx = step_ids.index('display_platform_database_header')

        assert start_idx < header_idx, \
            "start_test_containers should come before display_platform_database_header"

    def test_start_test_containers_action_exists(self):
        """Should have start_test_containers action in actions.py."""
        from wizard.services.base_platform import actions

        assert hasattr(actions, 'start_test_containers'), \
            "actions.py should have start_test_containers function"


class TestHeaderActionBehavior:
    """Tests that header actions display properly formatted output."""

    def test_base_platform_header_uses_formatting_library(self):
        """display_base_platform_header should use print_section from formatting library."""
        from wizard.services.base_platform import actions
        from unittest.mock import Mock

        # Create mock runner
        runner = Mock()
        runner.display = Mock()
        ctx = {}

        # Call the action
        actions.display_base_platform_header(ctx, runner)

        # Should have called display at least once
        assert runner.display.called, "Should call runner.display"

        # Check that it displays proper content
        calls = [str(call) for call in runner.display.call_args_list]
        output = ' '.join(calls)

        # Should contain newline before header (for visual separation)
        assert runner.display.call_args_list[0][0][0] == "", \
            "First call should be empty string (newline)"

        # Should mention "Base Platform" in output
        assert any('Base Platform' in str(call) for call in runner.display.call_args_list), \
            "Should display 'Base Platform' text"

    def test_test_containers_header_format(self):
        """display_test_containers_header should display with proper format."""
        from wizard.services.base_platform import actions
        from unittest.mock import Mock

        runner = Mock()
        runner.display = Mock()
        ctx = {}

        actions.display_test_containers_header(ctx, runner)

        # Should have newline before header
        assert runner.display.call_args_list[0][0][0] == "", \
            "First call should be empty string (newline)"

        # Should mention test containers
        calls = [str(call) for call in runner.display.call_args_list]
        output = ' '.join(calls)
        assert any('Connectivity Test' in str(call) or 'Test Container' in str(call)
                  for call in runner.display.call_args_list), \
            "Should display connectivity test or test container text"

    def test_platform_database_header_format(self):
        """display_platform_database_header should display with proper format."""
        from wizard.services.base_platform import actions
        from unittest.mock import Mock

        runner = Mock()
        runner.display = Mock()
        ctx = {}

        actions.display_platform_database_header(ctx, runner)

        # Should have newline before header
        assert runner.display.call_args_list[0][0][0] == "", \
            "First call should be empty string (newline)"

        # Should mention platform database
        assert any('Platform' in str(call) and 'Database' in str(call)
                  for call in runner.display.call_args_list), \
            "Should display platform database text"
