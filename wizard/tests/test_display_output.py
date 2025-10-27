"""Tests for display output functionality."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestMessageInterpolation:
    """Test interpolating {variables} in display prompts."""

    def test_interpolate_simple_variable(self):
        """Should replace {key} with state value."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Set state
        engine.state['total_artifacts'] = 5

        # Interpolate message
        result = engine._interpolate_prompt("Found {total_artifacts} artifacts", engine.state)

        assert result == "Found 5 artifacts"

    def test_interpolate_multiple_variables(self):
        """Should replace multiple {variables}."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.state['containers'] = 3
        engine.state['images'] = 7

        result = engine._interpolate_prompt(
            "Containers: {containers}, Images: {images}",
            engine.state
        )

        assert result == "Containers: 3, Images: 7"

    def test_interpolate_preserves_missing_keys(self):
        """Should preserve {key} if not in state."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        result = engine._interpolate_prompt("Found {missing_key} items", engine.state)

        assert result == "Found {missing_key} items"

    def test_interpolate_handles_nested_keys(self):
        """Should handle dot-notation keys like services.postgres.enabled."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.state['services.postgres.enabled'] = True

        result = engine._interpolate_prompt(
            "Postgres enabled: {services.postgres.enabled}",
            engine.state
        )

        assert result == "Postgres enabled: True"


class TestDisplayStepExecution:
    """Test that display steps actually display output."""

    def test_display_step_calls_runner_display(self):
        """Display step should call runner.display()."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute a simple spec with display step
        from wizard.engine.schema import ServiceSpec, Step
        spec = ServiceSpec(
            service='test',
            version='1.0',
            description='Test',
            requires=[],
            provides=[],
            steps=[
                Step(
                    id='show_message',
                    type='display',
                    prompt='Test message',
                    next=None
                )
            ]
        )

        engine._execute_flow_steps(spec.steps, {})

        # Should have called display
        assert ('display', 'Test message') in runner.calls

    def test_display_step_interpolates_variables(self):
        """Display step should interpolate {variables} from state."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.state['count'] = 42

        from wizard.engine.schema import ServiceSpec, Step
        spec = ServiceSpec(
            service='test',
            version='1.0',
            description='Test',
            requires=[],
            provides=[],
            steps=[
                Step(
                    id='show_count',
                    type='display',
                    prompt='Count: {count}',
                    next=None
                )
            ]
        )

        engine._execute_flow_steps(spec.steps, {})

        assert ('display', 'Count: 42') in runner.calls
