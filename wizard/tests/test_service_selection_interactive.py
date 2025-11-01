"""Tests for service selection using boolean questions."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestBooleanServiceSelection:
    """Test service selection with individual Y/N questions."""

    def test_service_selection_asks_three_boolean_questions(self):
        """Should ask Y/N for openmetadata, kerberos, pagila."""
        runner = MockActionRunner()
        runner.input_queue = [
            'y',  # Install OpenMetadata? y
            'n',  # Install Kerberos? n
            'y',  # Install Pagila? y
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have asked 3 boolean questions
        service_questions = [
            c for c in runner.calls
            if c[0] == 'get_input' and 'Install' in c[1]
        ]
        assert len(service_questions) == 3

    def test_yes_answers_enable_services(self):
        """Answering 'y' should enable the service."""
        runner = MockActionRunner()
        runner.input_queue = [
            'y',  # OpenMetadata: YES
            'y',  # Kerberos: YES
            'n',  # Pagila: NO
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Verify state
        assert engine.state.get('services.openmetadata.enabled') == True
        assert engine.state.get('services.kerberos.enabled') == True
        assert engine.state.get('services.pagila.enabled') == False

    def test_no_answers_disable_services(self):
        """Answering 'n' (or Enter for default) should disable services."""
        runner = MockActionRunner()
        runner.input_queue = [
            '',  # OpenMetadata: default (no)
            '',  # Kerberos: default (no)
            '',  # Pagila: default (no)
            '', '', '', '', ''  # Postgres defaults
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Only postgres should be enabled
        assert engine.state.get('services.base_platform.postgres.enabled') == True
        assert engine.state.get('services.openmetadata.enabled') == False
        assert engine.state.get('services.kerberos.enabled') == False
        assert engine.state.get('services.pagila.enabled') == False

    def test_prompts_are_clear_and_simple(self):
        """Prompts should be simple Y/N questions."""
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', '', '', '', '', '']

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Check prompt format
        questions = [
            c for c in runner.calls
            if c[0] == 'get_input' and 'Install' in c[1]
        ]

        # Should have clear format: "Install ServiceName?"
        assert any('Install OpenMetadata?' in c[1] for c in questions)
        assert any('Install Kerberos?' in c[1] for c in questions)
        assert any('Install Pagila?' in c[1] for c in questions)
