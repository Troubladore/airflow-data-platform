"""Tests for display output during service execution."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestServicePromptDisplay:
    """Test that service prompts are displayed to users."""

    def test_service_string_step_shows_prompt(self):
        """String-type steps should display their prompt."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute postgres service with headless inputs
        engine.execute_flow('setup', headless_inputs={
            'select_openmetadata': 'n',
            'select_kerberos': 'n',
            'select_pagila': 'n',
            'postgres_image': 'postgres:17.5'  # Provide input
        })

        # Should have displayed the prompt
        prompts_displayed = [call for call in runner.calls if call[0] == 'display']
        assert len(prompts_displayed) > 0
        # Check for postgres image prompt
        assert any('PostgreSQL image' in str(call) for call in prompts_displayed)

    def test_service_boolean_step_shows_prompt(self):
        """Boolean-type steps should display their prompt."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.execute_flow('setup', headless_inputs={
            'select_openmetadata': 'n',
            'select_kerberos': 'n',
            'select_pagila': 'n',
            'postgres_image': 'custom:image',
            'postgres_prebuilt': 'y'
        })

        # Should have displayed prebuilt prompt
        prompts = [call for call in runner.calls if call[0] == 'display']
        assert any('prebuilt' in str(call).lower() for call in prompts)

    def test_service_enum_step_shows_prompt(self):
        """Enum-type steps should display their prompt."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.execute_flow('setup', headless_inputs={
            'select_openmetadata': 'n',
            'select_kerberos': 'n',
            'select_pagila': 'n',
            'postgres_image': 'postgres:17.5',
            'postgres_auth': 'md5'
        })

        # Should have displayed auth method prompt
        prompts = [call for call in runner.calls if call[0] == 'display']
        assert any('authentication method' in str(call).lower() for call in prompts)

    def test_service_integer_step_shows_prompt(self):
        """Integer-type steps should display their prompt."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.execute_flow('setup', headless_inputs={
            'select_openmetadata': 'n',
            'select_kerberos': 'n',
            'select_pagila': 'n',
            'postgres_image': 'postgres:17.5',
            'postgres_auth': 'trust',
            'postgres_port': 5432  # Integer, not string
        })

        # Should have displayed port prompt
        prompts = [call for call in runner.calls if call[0] == 'display']
        assert any('port' in str(call).lower() for call in prompts)

    def test_service_display_step_shows_message(self):
        """Display-type steps in services should show their message."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        engine.execute_flow('setup', headless_inputs={
            'select_openmetadata': 'n',
            'select_kerberos': 'n',
            'select_pagila': 'n',
            'postgres_image': ''  # Use default
        })

        # Should display messages from service
        displays = [call for call in runner.calls if call[0] == 'display']
        assert len(displays) > 0
