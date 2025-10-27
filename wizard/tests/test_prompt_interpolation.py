"""Test that prompt placeholders are interpolated correctly.

This is a regression test suite for the {current_value} interpolation bug,
where prompts showed literal {current_value} text instead of actual default values.

The fix ensures that:
1. current_value is set in state before prompt interpolation
2. _interpolate_prompt() replaces {current_value} with the actual default
3. Runner receives a fully-interpolated prompt string
"""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestPromptInterpolation:
    """Test that {variables} in prompts are replaced with state values."""

    def test_current_value_not_in_prompts(self):
        """Prompts should never show literal {current_value} placeholder.

        This is the main regression test. If this fails, it means:
        - Either current_value is not being set in state before interpolation
        - Or _interpolate_prompt() is not being called
        - Or the prompt template contains {current_value} but state is empty
        """
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'postgres:17.5']

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup', headless_inputs=None)

        # Check all get_input calls for {current_value}
        input_calls = [c for c in runner.calls if c[0] == 'get_input']

        for call in input_calls:
            prompt = call[1]
            assert '{current_value}' not in prompt, \
                f"Found literal {{current_value}} in prompt: '{prompt}'"

    def test_prompts_show_actual_defaults(self):
        """Prompts should show actual default values in the prompt text.

        When a prompt has a default value, the user should see that value
        in the prompt, not a placeholder like {current_value}.
        """
        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'postgres:17.5']

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup', headless_inputs=None)

        # Find the postgres image prompt
        input_calls = [c for c in runner.calls if c[0] == 'get_input']
        postgres_prompts = [c for c in input_calls if 'PostgreSQL' in c[1] and 'image' in c[1].lower()]

        assert len(postgres_prompts) > 0, "Should have prompted for postgres image"

        prompt, default = postgres_prompts[0][1], postgres_prompts[0][2]

        # The prompt should not contain {current_value}
        assert '{current_value}' not in prompt
        # The default should be the actual value
        assert default == 'postgres:17.5-alpine'

    def test_interpolate_prompt_with_current_value(self):
        """Test _interpolate_prompt() directly with {current_value} placeholder.

        This tests the interpolation function itself to ensure it can handle
        {current_value} placeholders when they exist in the prompt template.
        """
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Set current_value in state
        engine.state['current_value'] = 'test-value-123'

        # Test interpolation
        template = "Please enter value [{current_value}]"
        result = engine._interpolate_prompt(template, engine.state)

        assert result == "Please enter value [test-value-123]"
        assert '{current_value}' not in result

    def test_interpolate_prompt_with_missing_value(self):
        """Test _interpolate_prompt() behavior when placeholder has no state value.

        When a placeholder like {current_value} is in the template but not in state,
        the interpolation should keep the placeholder (rather than crashing or
        showing empty string).
        """
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Empty state - no current_value
        template = "Please enter value [{current_value}]"
        result = engine._interpolate_prompt(template, engine.state)

        # Should keep placeholder if value not found
        assert result == "Please enter value [{current_value}]"

    def test_interpolate_prompt_with_multiple_placeholders(self):
        """Test _interpolate_prompt() with multiple different placeholders."""
        runner = MockActionRunner()
        engine = WizardEngine(runner=runner, base_path='wizard')

        # Set multiple state values
        engine.state['current_value'] = 'value1'
        engine.state['other_value'] = 'value2'

        template = "Enter {current_value} or {other_value}"
        result = engine._interpolate_prompt(template, engine.state)

        assert result == "Enter value1 or value2"
        assert '{' not in result or '}' not in result

    def test_no_uninterpolated_placeholders_in_any_prompt(self):
        """Comprehensive check: no {word} patterns should appear in ANY prompt.

        This is a broad safety net that catches any placeholder that wasn't
        properly interpolated, not just {current_value}.
        """
        import re

        runner = MockActionRunner()
        runner.input_queue = ['n', 'n', 'n', 'postgres:17.5']

        engine = WizardEngine(runner=runner, base_path='wizard')
        engine.execute_flow('setup', headless_inputs=None)

        # Pattern to match {word} style placeholders
        placeholder_pattern = r'\{[a-zA-Z_][a-zA-Z0-9_]*\}'

        input_calls = [c for c in runner.calls if c[0] == 'get_input']

        for call in input_calls:
            prompt = call[1]
            matches = re.findall(placeholder_pattern, prompt)

            assert len(matches) == 0, \
                f"Found uninterpolated placeholders {matches} in prompt: '{prompt}'"
