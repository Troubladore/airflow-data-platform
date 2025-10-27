"""Tests for interactive input collection."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestInteractiveMode:
    """Test wizard runs in interactive mode when headless_inputs not provided."""

    def test_interactive_mode_when_no_headless_inputs(self):
        """Should use interactive mode when headless_inputs is None."""
        runner = MockActionRunner()
        runner.input_queue = ['postgres:17.5']

        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute WITHOUT headless_inputs
        engine.execute_flow('setup', headless_inputs=None)

        # Should have called get_input
        input_calls = [c for c in runner.calls if c[0] == 'get_input']
        assert len(input_calls) > 0

    def test_headless_mode_when_dict_provided(self):
        """Should use headless mode when headless_inputs dict provided."""
        runner = MockActionRunner()

        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute WITH headless_inputs (must use valid image format)
        engine.execute_flow('setup', headless_inputs={'postgres_image': 'postgres:17.5'})

        # Should NOT have called get_input
        input_calls = [c for c in runner.calls if c[0] == 'get_input']
        assert len(input_calls) == 0  # Uses headless_inputs dict instead


class TestInputCollection:
    """Test collecting input from user."""

    def test_string_step_collects_input(self):
        """String-type steps should call get_input()."""
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'custom:image']  # Service selections + postgres image

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have requested postgres image
        input_calls = [c for c in runner.calls if c[0] == 'get_input']
        assert any('PostgreSQL image' in str(c) for c in input_calls)

    def test_boolean_step_collects_input(self):
        """Boolean-type steps should call get_input()."""
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'postgres:17.5', 'y']  # Selections + image + prebuilt

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have requested prebuilt choice
        input_calls = [c for c in runner.calls if c[0] == 'get_input']
        assert any('prebuilt' in str(c).lower() for c in input_calls)

    def test_uses_input_response_in_state(self):
        """Should store user's input response in state."""
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'custom:image']

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # State should contain user's response
        assert engine.state.get('services.postgres.image') == 'custom:image'


class TestValidationLoop:
    """Test re-prompting on invalid input."""

    def test_reprompts_on_validation_error_interactive(self):
        """Should re-prompt when validation fails in interactive mode."""
        runner = MockActionRunner()
        runner.input_queue = [
            'n', 'n', 'n',  # Service selections
            'invalid!@#$',  # Invalid image URL
            'postgres:17.5' # Valid image URL
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have called get_input twice for postgres_image (retry after error)
        image_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'image' in str(c).lower()]
        assert len(image_prompts) >= 2

    def test_shows_error_message_on_invalid_input(self):
        """Should display error message when validation fails."""
        runner = MockActionRunner()
        runner.input_queue = [
            'n', 'n', 'n',
            '999999',      # Invalid port
            '5432'         # Valid port
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have displayed error message
        error_displays = [c for c in runner.calls if c[0] == 'display' and 'Error' in str(c)]
        assert len(error_displays) > 0
