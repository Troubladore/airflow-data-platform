# Interactive Input System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add interactive input collection so wizard actually waits for user responses instead of silently using defaults.

**Architecture:** Add get_input(prompt, default) to ActionRunner interface. RealActionRunner reads from stdin, MockActionRunner uses input_queue. Engine tracks headless_mode flag and calls runner.get_input() when interactive.

**Tech Stack:** Python 3.12, existing wizard architecture (runner interface, engine)

---

## Task 22a: Interactive Input (RED Phase)

**Files:**
- Modify: `wizard/engine/runner.py`
- Modify: `wizard/tests/test_runner.py`
- Create: `wizard/tests/test_interactive_input.py`

**Step 1: Write failing tests for runner.get_input()**

Add to `wizard/tests/test_runner.py`:

```python
class TestGetInputMethod:
    """Test get_input() method in ActionRunner implementations."""

    def test_real_runner_has_get_input_method(self):
        """RealActionRunner should have get_input() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_has_get_input_method(self):
        """MockActionRunner should have get_input() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'get_input')
        assert callable(runner.get_input)

    def test_mock_runner_captures_get_input_calls(self):
        """MockActionRunner should record get_input() calls."""
        runner = MockActionRunner()

        result = runner.get_input("Enter name:", "default")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('get_input', 'Enter name:', 'default')

    def test_mock_runner_returns_from_input_queue(self):
        """MockActionRunner should return values from input_queue."""
        runner = MockActionRunner()
        runner.input_queue = ['value1', 'value2']

        result1 = runner.get_input("Prompt 1:", None)
        result2 = runner.get_input("Prompt 2:", None)

        assert result1 == 'value1'
        assert result2 == 'value2'

    def test_mock_runner_returns_default_when_queue_empty(self):
        """MockActionRunner should return default if input_queue empty."""
        runner = MockActionRunner()
        runner.input_queue = []

        result = runner.get_input("Prompt:", "default_value")

        assert result == 'default_value'
```

**Step 2: Write failing tests for interactive mode**

Create `wizard/tests/test_interactive_input.py`:

```python
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

        # Execute WITH headless_inputs
        engine.execute_flow('setup', headless_inputs={'postgres_image': 'custom'})

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
```

**Step 3: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_runner.py::TestGetInputMethod wizard/tests/test_interactive_input.py -v`

Expected: FAIL with "ActionRunner has no attribute 'get_input'"

**Step 4: Commit**

```bash
git add wizard/tests/test_runner.py wizard/tests/test_interactive_input.py
git commit -m "feat: add interactive input tests (RED phase)

Task 22a complete - tests for interactive user input collection.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 22b: Interactive Input (GREEN Phase)

**Files:**
- Modify: `wizard/engine/runner.py`
- Modify: `wizard/engine/engine.py`

**Step 1: Add get_input() to runner interface**

Modify `wizard/engine/runner.py`:

```python
from abc import ABC, abstractmethod
from typing import List, Dict, Any


class ActionRunner(ABC):
    """Abstract interface for all side effects."""

    # ... existing methods (save_config, run_shell, check_docker, file_exists, display) ...

    @abstractmethod
    def get_input(self, prompt: str, default: str = None) -> str:
        """Get input from user.

        Args:
            prompt: Question to ask user
            default: Default value if user presses Enter (shown in [brackets])

        Returns:
            User's input string (or default if empty)
        """
        pass


class RealActionRunner(ActionRunner):
    """Production runner - performs actual I/O."""

    # ... existing methods ...

    def get_input(self, prompt: str, default: str = None) -> str:
        """Read from stdin with optional default."""
        if default:
            # Show default in brackets
            full_prompt = f"{prompt} [{default}]: "
            response = input(full_prompt).strip()
            return response if response else default
        else:
            # No default
            full_prompt = f"{prompt}: "
            response = input(full_prompt).strip()
            return response


class MockActionRunner(ActionRunner):
    """Test runner - records calls and provides scripted responses."""

    def __init__(self):
        super().__init__()
        self.calls = []
        self.responses = {}
        self.input_queue = []  # NEW: Pre-scripted user inputs for testing

    # ... existing methods ...

    def get_input(self, prompt: str, default: str = None) -> str:
        """Return next value from input_queue."""
        self.calls.append(('get_input', prompt, default))

        # Pop next scripted response
        if self.input_queue:
            return self.input_queue.pop(0)

        # Fall back to default or empty string
        return default if default else ''
```

**Step 2: Run runner tests to verify they pass**

Run: `uv run pytest wizard/tests/test_runner.py::TestGetInputMethod -v`

Expected: 5 tests PASS

**Step 3: Add mode tracking to engine**

Modify `wizard/engine/engine.py` - in `execute_flow()` method:

```python
def execute_flow(self, flow_name: str, headless_inputs: Optional[Dict] = None):
    """Execute a flow.

    Args:
        flow_name: Flow to execute (setup, clean-slate)
        headless_inputs: Optional dict of pre-provided answers for testing
                        If None: INTERACTIVE mode (prompt user via stdin)
                        If provided: HEADLESS mode (use dict values)
    """
    # Determine mode
    self.headless_mode = (headless_inputs is not None)
    self.headless_inputs = headless_inputs or {}

    # ... rest of existing flow execution logic
```

**Step 4: Add input collection logic to engine**

Modify `wizard/engine/engine.py` - in `_execute_step()` method:

```python
def _execute_step(self, step, headless_inputs):
    """Execute a single step."""

    # Display steps (already working)
    if step.type == 'display':
        if step.prompt:
            message = self._interpolate_prompt(step.prompt, self.state)
            self.runner.display(message)
        return

    # Interactive steps (string, boolean, integer, enum)
    if step.type in ['string', 'boolean', 'integer', 'enum']:
        # Display prompt (already working)
        if step.prompt:
            prompt_text = self._interpolate_prompt(step.prompt, self.state)
            self.runner.display(prompt_text)

        # Collect input with validation
        user_input = self._get_validated_input(step)

        # Store in state
        if step.state_key:
            self.state[step.state_key] = user_input

        return

    # ... rest of step types (action, conditional, service)


def _get_validated_input(self, step) -> Any:
    """Get and validate user input with retry loop.

    Args:
        step: Step to collect input for

    Returns:
        Validated input value
    """
    while True:
        # Get input based on mode
        if self.headless_mode:
            # Use pre-provided answer from dict
            user_input = self.headless_inputs.get(step.id, step.default_value or '')
        else:
            # Ask user interactively
            default = step.default_value
            # Check for dynamic default from state
            if hasattr(step, 'default_from') and step.default_from:
                default = self.state.get(step.default_from, default)

            user_input = self.runner.get_input(step.prompt, default)

        # Validate if validator specified
        if step.validator:
            try:
                validated = self._run_validator(step.validator, user_input, self.state)
                return validated  # Success!
            except ValueError as e:
                if self.headless_mode:
                    # Fail fast in tests
                    raise
                else:
                    # Show error and re-prompt
                    self.runner.display(f"Error: {e}")
                    continue  # Loop back to get_input
        else:
            # No validation needed
            return user_input
```

**Step 5: Run all tests to verify they pass**

Run: `uv run pytest wizard/ platform-bootstrap/tests/ -v`

Expected: All tests PASS (428+ existing tests continue to work in headless mode)

**Step 6: Run interactive tests specifically**

Run: `uv run pytest wizard/tests/test_interactive_input.py -v`

Expected: All new interactive tests PASS

**Step 7: Test manually**

Run: `./platform setup`

Expected: Wizard waits for user input at each prompt!

**Step 8: Commit**

```bash
git add wizard/engine/runner.py wizard/engine/engine.py
git commit -m "feat: implement interactive input collection (GREEN phase)

Task 22b complete - wizard now actually waits for user input!

Added:
- get_input() to ActionRunner interface
- input_queue to MockActionRunner for testing
- headless_mode tracking in WizardEngine
- _get_validated_input() with retry loop for validation errors

Users can now interactively answer wizard prompts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 22c: Interactive Input (Code Review)

**Step 1: Run code review**

Use superpowers:code-reviewer to validate implementation.

**Step 2: Address any issues found**

Fix problems identified by code review.

**Step 3: Verify all tests pass**

Run: `uv run pytest wizard/ platform-bootstrap/tests/ -v`

Expected: All tests PASS

**Step 4: Test user experience manually**

Test both modes:

```bash
# Interactive mode (real user experience)
./platform setup
# Should prompt for each question and wait for answers

# Headless mode (for automation)
# Tests already verify this works
uv run pytest wizard/tests/test_setup_flow.py -v
```

**Step 5: Commit fixes if any**

```bash
git add <modified-files>
git commit -m "fix: address code review feedback for interactive input

Task 22c complete - interactive input reviewed and approved.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Success Criteria

- ✅ All tests passing (440+ including new interactive tests)
- ✅ Interactive mode waits for user input
- ✅ Headless mode continues to work for all existing tests
- ✅ Validation errors show and re-prompt
- ✅ Users can actually use the wizard interactively
- ✅ No regressions in existing functionality

---

## Critical Note

**This fixes the fundamental UX issue:** Wizard was displaying prompts but never waiting for input. After this task, users will be able to actually interact with the wizard.

**Why this was missed:** All 428 tests use headless mode (pre-provided answers). We never tested actual interactive stdin collection.

**Lesson learned:** Need at least one end-to-end interactive test (even if mocked via input_queue) to catch this class of issue.
