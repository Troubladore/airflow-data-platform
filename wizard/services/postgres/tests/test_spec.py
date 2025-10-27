"""Tests for PostgreSQL spec.yaml - RED phase."""

import pytest
import yaml
from pathlib import Path


class TestSpecLoads:
    """Tests for spec.yaml loading."""

    def test_spec_loads(self):
        """Should load spec.yaml successfully."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        assert spec_path.exists(), "spec.yaml should exist"

        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        assert spec is not None, "spec.yaml should contain valid YAML"
        assert isinstance(spec, dict), "spec.yaml should be a dictionary"


class TestSpecRequiredFields:
    """Tests for required fields in spec.yaml."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_spec_has_service_field(self, spec):
        """Should have 'service' field."""
        assert 'service' in spec, "spec.yaml must have 'service' field"
        assert spec['service'] == 'postgres', "service should be 'postgres'"

    def test_spec_has_version_field(self, spec):
        """Should have 'version' field."""
        assert 'version' in spec, "spec.yaml must have 'version' field"
        assert isinstance(spec['version'], (str, float, int)), "version should be string or number"

    def test_spec_has_provides_field(self, spec):
        """Should have 'provides' field."""
        assert 'provides' in spec, "spec.yaml must have 'provides' field"
        assert isinstance(spec['provides'], list), "provides should be a list"
        assert 'db.postgres' in spec['provides'], "should provide 'db.postgres' capability"

    def test_spec_has_description_field(self, spec):
        """Should have 'description' field."""
        assert 'description' in spec, "spec.yaml must have 'description' field"
        assert isinstance(spec['description'], str), "description should be a string"
        assert len(spec['description']) > 0, "description should not be empty"


class TestSpecStepsValid:
    """Tests for step definitions in spec.yaml."""

    @pytest.fixture
    def spec(self):
        """Load spec.yaml for testing."""
        spec_path = Path(__file__).parent.parent / "spec.yaml"
        with open(spec_path) as f:
            return yaml.safe_load(f)

    def test_spec_has_steps_field(self, spec):
        """Should have 'steps' field."""
        assert 'steps' in spec, "spec.yaml must have 'steps' field"
        assert isinstance(spec['steps'], list), "steps should be a list"
        assert len(spec['steps']) > 0, "steps should not be empty"

    def test_spec_steps_have_required_fields(self, spec):
        """Each step should have required fields."""
        for i, step in enumerate(spec['steps']):
            assert 'id' in step, f"step {i} must have 'id' field"
            assert 'type' in step, f"step {i} must have 'type' field"

            # Non-action steps need prompts
            if step['type'] != 'action':
                assert 'prompt' in step, f"step {i} (non-action) must have 'prompt' field"

    def test_spec_has_postgres_image_step(self, spec):
        """Should have postgres_image step with validator."""
        steps = {s['id']: s for s in spec['steps']}
        assert 'postgres_image' in steps, "should have postgres_image step"

        step = steps['postgres_image']
        assert step['type'] == 'string', "postgres_image should be type 'string'"
        assert 'state_key' in step, "postgres_image should have state_key"
        assert step['state_key'] == 'services.postgres.image', "state_key should be services.postgres.image"
        assert 'validator' in step, "postgres_image should have validator"
        assert step['validator'] == 'postgres.validate_image_url', "should use postgres.validate_image_url"

    def test_spec_has_postgres_auth_step(self, spec):
        """Should have postgres_auth step."""
        steps = {s['id']: s for s in spec['steps']}
        assert 'postgres_auth' in steps, "should have postgres_auth step"

        step = steps['postgres_auth']
        assert step['type'] == 'boolean', "postgres_auth should be type 'boolean'"
        assert 'prompt' in step, "postgres_auth should have a prompt"
        assert step['state_key'] == 'services.postgres.require_password', "should store to require_password state key"

    def test_spec_has_postgres_save_action(self, spec):
        """Should have postgres_save action step."""
        steps = {s['id']: s for s in spec['steps']}
        assert 'postgres_save' in steps, "should have postgres_save step"

        step = steps['postgres_save']
        assert step['type'] == 'action', "postgres_save should be type 'action'"
        assert 'action' in step, "postgres_save should have action field"
        assert step['action'] == 'postgres.save_config', "should use postgres.save_config action"

    def test_spec_step_ids_are_unique(self, spec):
        """All step IDs should be unique."""
        step_ids = [s['id'] for s in spec['steps']]
        assert len(step_ids) == len(set(step_ids)), "step IDs must be unique"

    def test_spec_step_next_references_valid(self, spec):
        """Step 'next' references should point to valid step IDs or conditionals."""
        step_ids = {s['id'] for s in spec['steps']}
        valid_terminals = {'finish', 'end'}

        for step in spec['steps']:
            if 'next' in step:
                next_val = step['next']
                if isinstance(next_val, str):
                    # Simple next reference
                    assert next_val in step_ids or next_val in valid_terminals, \
                        f"step {step['id']} next='{next_val}' must reference valid step or terminal"
                elif isinstance(next_val, dict):
                    # Conditional next (when_changed/when_unchanged)
                    for key in ['when_changed', 'when_unchanged']:
                        if key in next_val:
                            target = next_val[key]
                            assert target in step_ids or target in valid_terminals, \
                                f"step {step['id']} {key}='{target}' must reference valid step or terminal"
