"""Tests for service selection in interactive mode."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestInteractiveServiceSelection:
    """Test service selection works in interactive mode."""

    def test_service_selection_prompts_user_interactive(self):
        """Should prompt for service selection in interactive mode."""
        runner = MockActionRunner()
        runner.input_queue = [
            'openmetadata kerberos',  # Select 2 services
            '', '', '', '', ''         # Postgres prompts (defaults)
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have prompted for service selection
        selection_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'Select services' in c[1]]
        assert len(selection_prompts) == 1

    def test_selected_services_are_enabled(self):
        """Services selected interactively should be enabled."""
        runner = MockActionRunner()
        runner.input_queue = [
            'openmetadata',  # Select only openmetadata
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # OpenMetadata should be enabled
        assert engine.state.get('services.openmetadata.enabled') == True
        assert engine.state.get('services.kerberos.enabled') == False
        assert engine.state.get('services.pagila.enabled') == False

    def test_empty_selection_enables_only_postgres(self):
        """Empty service selection should enable only postgres."""
        runner = MockActionRunner()
        runner.input_queue = [
            '',  # No services selected
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Only postgres should be enabled
        assert engine.state.get('services.postgres.enabled') == True
        assert engine.state.get('services.openmetadata.enabled') == False
        assert engine.state.get('services.kerberos.enabled') == False
        assert engine.state.get('services.pagila.enabled') == False

    def test_multiple_services_space_separated(self):
        """Should parse space-separated service list."""
        runner = MockActionRunner()
        runner.input_queue = [
            'openmetadata kerberos pagila',  # All services
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # All services should be enabled
        assert engine.state.get('services.postgres.enabled') == True
        assert engine.state.get('services.openmetadata.enabled') == True
        assert engine.state.get('services.kerberos.enabled') == True
        assert engine.state.get('services.pagila.enabled') == True
