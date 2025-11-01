"""Acceptance tests for setup wizard - happy path user scenarios."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestSetupHappyPath:
    """Test complete setup wizard flows from user perspective."""

    def test_all_defaults_completes_successfully(self):
        """User pressing Enter for all prompts should work."""
        runner = MockActionRunner()
        # Simulate pressing Enter (empty strings) for all inputs
        runner.input_queue = [
            '',   # Install OpenMetadata? (default: n)
            '',   # Install Kerberos? (default: n)
            '',   # Install Pagila? (default: n)
            '',   # Postgres image (use default)
            '',   # Prebuilt (use default False)
            '',   # Require password (use default True)
            '',   # Password (use default)
            ''    # Port (use default)
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Verify defaults were used
        assert engine.state['services.base_platform.postgres.image'] == 'postgres:17.5-alpine'
        assert engine.state['services.base_platform.postgres.prebuilt'] == False
        assert engine.state['services.base_platform.postgres.require_password'] == True
        assert engine.state['services.base_platform.postgres.password'] == 'changeme'
        assert engine.state['services.base_platform.postgres.port'] == 5432

    def test_custom_values_are_actually_used(self):
        """Custom user inputs should override defaults."""
        runner = MockActionRunner()
        runner.input_queue = [
            '',                    # Install OpenMetadata? (n)
            '',                    # Install Kerberos? (n)
            '',                    # Install Pagila? (n)
            'postgres:16',         # Custom image
            'y',                   # Yes to prebuilt
            'n',                   # No password required
            '5433'                 # Custom port (password skipped when not required)
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Verify custom values were stored
        assert engine.state['services.base_platform.postgres.image'] == 'postgres:16'
        assert engine.state['services.base_platform.postgres.prebuilt'] == True
        assert engine.state['services.base_platform.postgres.require_password'] == False
        assert engine.state['services.base_platform.postgres.port'] == 5433

    def test_each_prompt_only_asked_once(self):
        """Each question should only be asked once (no duplicate prompts)."""
        runner = MockActionRunner()
        runner.input_queue = ['', '', '', '', '', '', '', '']  # 3 service selection + 5 postgres prompts

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Count prompts for each field (use more specific matching to avoid overlaps)
        image_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'PostgreSQL Docker image' in c[1]]
        prebuilt_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'prebuilt' in c[1].lower()]
        password_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'password' in c[1].lower()]
        port_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'PostgreSQL port' in c[1]]

        # Each should only be asked once
        assert len(image_prompts) == 1, f"Image prompted {len(image_prompts)} times, expected 1"
        assert len(prebuilt_prompts) == 1, f"Prebuilt prompted {len(prebuilt_prompts)} times, expected 1"
        assert len(password_prompts) == 2, f"Password (require + actual) prompted {len(password_prompts)} times, expected 2"
        assert len(port_prompts) == 1, f"Port prompted {len(port_prompts)} times, expected 1"

    def test_validation_errors_reprompt(self):
        """Invalid input should show error and ask again."""
        runner = MockActionRunner()
        runner.input_queue = [
            '',            # Install OpenMetadata? (n)
            '',            # Install Kerberos? (n)
            '',            # Install Pagila? (n)
            '',            # Image default
            '',            # Prebuilt default
            '',            # Auth default
            '',            # Password default
            '999999',      # Invalid port (too high)
            '5433'         # Valid port
        ]

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup')

        # Should have prompted for port twice
        port_prompts = [c for c in runner.calls if c[0] == 'get_input' and 'port' in c[1].lower()]
        assert len(port_prompts) == 2, "Should re-prompt after validation error"

        # Should have displayed error message
        error_displays = [c for c in runner.calls if c[0] == 'display' and 'Error' in str(c)]
        assert len(error_displays) >= 1, "Should show validation error"

        # Should store valid port
        assert engine.state['services.base_platform.postgres.port'] == 5433
