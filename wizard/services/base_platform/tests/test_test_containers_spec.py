"""Tests for test-containers sub-spec - RED phase.

This file tests the test-containers-spec.yaml sub-spec that will be loaded
by the main base_platform spec to configure test container images.
"""

import pytest
import yaml
from pathlib import Path


class TestSubSpecFileExists:
    """Test that the sub-spec file exists."""

    def test_sub_spec_file_exists(self):
        """Should have test-containers-spec.yaml file."""
        spec_path = Path(__file__).parent.parent / "test-containers-spec.yaml"
        assert spec_path.exists(), "test-containers-spec.yaml should exist in base_platform service directory"


class TestSubSpecLoads:
    """Test that the sub-spec loads correctly."""

    @pytest.fixture
    def spec_path(self):
        """Path to the test-containers sub-spec."""
        return Path(__file__).parent.parent / "test-containers-spec.yaml"

    def test_sub_spec_loads(self, spec_path):
        """Should load test-containers-spec.yaml successfully."""
        # This will fail if file doesn't exist
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        assert spec is not None, "test-containers-spec.yaml should contain valid YAML"
        assert isinstance(spec, dict), "test-containers-spec.yaml should be a dictionary"

    def test_sub_spec_has_required_fields(self, spec_path):
        """Should have required top-level fields."""
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        assert 'service' in spec, "sub-spec must have 'service' field"
        assert spec['service'] == 'base_platform', "service should be 'base_platform'"
        assert 'version' in spec, "sub-spec must have 'version' field"
        assert 'description' in spec, "sub-spec must have 'description' field"
        assert 'steps' in spec, "sub-spec must have 'steps' field"
        assert isinstance(spec['steps'], list), "steps should be a list"


class TestPostgresTestSteps:
    """Test postgres_test configuration steps."""

    @pytest.fixture
    def spec(self):
        """Load test-containers sub-spec."""
        spec_path = Path(__file__).parent.parent / "test-containers-spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    @pytest.fixture
    def steps(self, spec):
        """Get steps as a dictionary keyed by ID."""
        return {s['id']: s for s in spec['steps']}

    def test_has_postgres_test_prebuilt_step(self, steps):
        """Should have postgres_test_prebuilt boolean step."""
        assert 'postgres_test_prebuilt' in steps, "should have postgres_test_prebuilt step"

        step = steps['postgres_test_prebuilt']
        assert step['type'] == 'boolean', "postgres_test_prebuilt should be type 'boolean'"
        assert 'state_key' in step, "postgres_test_prebuilt should have state_key"
        assert step['state_key'] == 'services.base_platform.test_containers.postgres_test.prebuilt', \
            "state_key should be services.base_platform.test_containers.postgres_test.prebuilt"
        assert 'default_value' in step, "postgres_test_prebuilt should have default_value"
        assert step['default_value'] is False, "default should be false (build from source)"

    def test_has_postgres_test_image_step(self, steps):
        """Should have postgres_test_image string step."""
        assert 'postgres_test_image' in steps, "should have postgres_test_image step"

        step = steps['postgres_test_image']
        assert step['type'] == 'string', "postgres_test_image should be type 'string'"
        assert 'state_key' in step, "postgres_test_image should have state_key"
        assert step['state_key'] == 'services.base_platform.test_containers.postgres_test.image', \
            "state_key should be services.base_platform.test_containers.postgres_test.image"
        assert 'default_value' in step, "postgres_test_image should have default_value"
        assert step['default_value'] == 'alpine:latest', "default should be alpine:latest"


class TestSqlcmdTestSteps:
    """Test sqlcmd_test configuration steps."""

    @pytest.fixture
    def spec(self):
        """Load test-containers sub-spec."""
        spec_path = Path(__file__).parent.parent / "test-containers-spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    @pytest.fixture
    def steps(self, spec):
        """Get steps as a dictionary keyed by ID."""
        return {s['id']: s for s in spec['steps']}

    def test_has_sqlcmd_test_prebuilt_step(self, steps):
        """Should have sqlcmd_test_prebuilt boolean step."""
        assert 'sqlcmd_test_prebuilt' in steps, "should have sqlcmd_test_prebuilt step"

        step = steps['sqlcmd_test_prebuilt']
        assert step['type'] == 'boolean', "sqlcmd_test_prebuilt should be type 'boolean'"
        assert 'state_key' in step, "sqlcmd_test_prebuilt should have state_key"
        assert step['state_key'] == 'services.base_platform.test_containers.sqlcmd_test.prebuilt', \
            "state_key should be services.base_platform.test_containers.sqlcmd_test.prebuilt"
        assert 'default_value' in step, "sqlcmd_test_prebuilt should have default_value"
        assert step['default_value'] is False, "default should be false (build from source)"

    def test_has_sqlcmd_test_image_step(self, steps):
        """Should have sqlcmd_test_image string step."""
        assert 'sqlcmd_test_image' in steps, "should have sqlcmd_test_image step"

        step = steps['sqlcmd_test_image']
        assert step['type'] == 'string', "sqlcmd_test_image should be type 'string'"
        assert 'state_key' in step, "sqlcmd_test_image should have state_key"
        assert step['state_key'] == 'services.base_platform.test_containers.sqlcmd_test.image', \
            "state_key should be services.base_platform.test_containers.sqlcmd_test.image"
        assert 'default_value' in step, "sqlcmd_test_image should have default_value"
        assert step['default_value'] == 'alpine:latest', "default should be alpine:latest"


class TestSaveConfigAction:
    """Test save_test_config action step."""

    @pytest.fixture
    def spec(self):
        """Load test-containers sub-spec."""
        spec_path = Path(__file__).parent.parent / "test-containers-spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    @pytest.fixture
    def steps(self, spec):
        """Get steps as a dictionary keyed by ID."""
        return {s['id']: s for s in spec['steps']}

    def test_has_save_config_action(self, steps):
        """Should have save_test_config action step."""
        assert 'save_test_config' in steps, "should have save_test_config step"

        step = steps['save_test_config']
        assert step['type'] == 'action', "save_test_config should be type 'action'"
        assert 'action' in step, "save_test_config should have action field"
        assert step['action'] == 'base_platform.save_test_container_config', \
            "should use base_platform.save_test_container_config action"
