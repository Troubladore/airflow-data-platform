# Display Output System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add display() method to runner interface so wizard can show messages to users during execution.

**Architecture:** Add display(message) as abstract method in ActionRunner. RealActionRunner prints to stdout, MockActionRunner captures calls. Engine calls runner.display() when executing display-type steps.

**Tech Stack:** Python 3.12, existing wizard architecture (runner interface, engine)

---

## Task 20a: Display Output (RED Phase)

**Files:**
- Modify: `wizard/engine/runner.py`
- Modify: `wizard/tests/test_runner.py`
- Modify: `wizard/engine/engine.py`
- Create: `wizard/tests/test_display_output.py`

**Step 1: Write failing tests for runner.display()**

Add to `wizard/tests/test_runner.py`:

```python
class TestDisplayMethod:
    """Test display() method in ActionRunner implementations."""

    def test_real_runner_has_display_method(self):
        """RealActionRunner should have display() method."""
        runner = RealActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_has_display_method(self):
        """MockActionRunner should have display() method."""
        runner = MockActionRunner()
        assert hasattr(runner, 'display')
        assert callable(runner.display)

    def test_mock_runner_captures_display_calls(self):
        """MockActionRunner should record display() calls."""
        runner = MockActionRunner()

        runner.display("Test message")

        assert len(runner.calls) == 1
        assert runner.calls[0] == ('display', 'Test message')

    def test_mock_runner_captures_multiple_displays(self):
        """MockActionRunner should record multiple display calls."""
        runner = MockActionRunner()

        runner.display("Message 1")
        runner.display("Message 2")

        assert len(runner.calls) == 2
        assert runner.calls[0] == ('display', 'Message 1')
        assert runner.calls[1] == ('display', 'Message 2')
```

**Step 2: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_runner.py::TestDisplayMethod -v`

Expected: FAIL with "ActionRunner has no attribute 'display'"

**Step 3: Write failing tests for message interpolation**

Create `wizard/tests/test_display_output.py`:

```python
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

        engine._execute_service_steps(spec.steps, {})

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

        engine._execute_service_steps(spec.steps, {})

        assert ('display', 'Count: 42') in runner.calls
```

**Step 4: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_display_output.py -v`

Expected: FAIL with "WizardEngine has no attribute '_interpolate_prompt'"

**Step 5: Commit**

```bash
git add wizard/tests/test_runner.py wizard/tests/test_display_output.py
git commit -m "feat: add display output tests (RED phase)

Task 20a complete - display tests written and failing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 20b: Display Output (GREEN Phase)

**Files:**
- Modify: `wizard/engine/runner.py`
- Modify: `wizard/engine/engine.py`

**Step 1: Add display() to ActionRunner interface**

Modify `wizard/engine/runner.py`:

```python
from abc import ABC, abstractmethod
from typing import List, Dict, Any


class ActionRunner(ABC):
    """Abstract interface for all side effects."""

    # ... existing methods ...

    @abstractmethod
    def display(self, message: str) -> None:
        """Display a message to the user.

        Args:
            message: Text to display (may contain newlines)
        """
        pass


class RealActionRunner(ActionRunner):
    """Production runner - performs actual operations."""

    # ... existing methods ...

    def display(self, message: str) -> None:
        """Print message to stdout."""
        print(message)


class MockActionRunner(ActionRunner):
    """Test runner - records calls without side effects."""

    # ... existing methods ...

    def display(self, message: str) -> None:
        """Capture display call for test verification."""
        self.calls.append(('display', message))
```

**Step 2: Run runner tests to verify they pass**

Run: `uv run pytest wizard/tests/test_runner.py::TestDisplayMethod -v`

Expected: 4 tests PASS

**Step 3: Add message interpolation to engine**

Add to `wizard/engine/engine.py`:

```python
import re  # Add to imports at top

class WizardEngine:
    # ... existing code ...

    def _interpolate_prompt(self, prompt: str, state: dict) -> str:
        """Replace {key} placeholders with state values.

        Args:
            prompt: Template string with {placeholders}
            state: Current wizard state

        Returns:
            Interpolated string with values filled in

        Examples:
            >>> engine._interpolate_prompt("Found {count} items", {'count': 5})
            'Found 5 items'
        """
        def replacer(match):
            key = match.group(1)
            value = state.get(key, f'{{{key}}}')  # Keep {key} if not found
            return str(value)

        return re.sub(r'\{([^}]+)\}', replacer, prompt)
```

**Step 4: Run interpolation tests to verify they pass**

Run: `uv run pytest wizard/tests/test_display_output.py::TestMessageInterpolation -v`

Expected: 4 tests PASS

**Step 5: Add display step handling to engine**

Modify `_execute_step()` in `wizard/engine/engine.py`:

```python
def _execute_step(self, step, headless_inputs):
    """Execute a single step."""

    # Handle display steps
    if step.type == 'display':
        if step.prompt:
            message = self._interpolate_prompt(step.prompt, self.state)
            self.runner.display(message)
        return  # Display steps don't collect input

    # ... existing action, boolean, string, conditional handling
```

**Step 6: Run display step execution tests**

Run: `uv run pytest wizard/tests/test_display_output.py::TestDisplayStepExecution -v`

Expected: 2 tests PASS

**Step 7: Run all tests to verify no regressions**

Run: `uv run pytest wizard/ platform-bootstrap/tests/test_platform_cli.py -v`

Expected: All tests PASS (413+)

**Step 8: Commit**

```bash
git add wizard/engine/runner.py wizard/engine/engine.py
git commit -m "feat: implement display output via runner interface (GREEN phase)

Task 20b complete - display steps now show messages to users.

Added:
- display() method to ActionRunner interface
- _interpolate_prompt() helper for variable substitution
- Display step handling in _execute_step()

All tests passing. Users now see discovery results and status messages.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 20c: Display Output (Code Review)

**Step 1: Run code review**

Use superpowers:code-reviewer to validate implementation.

**Step 2: Address any issues found**

Fix problems identified by code review.

**Step 3: Verify all tests pass**

Run: `uv run pytest wizard/ platform-bootstrap/tests/ -v`

Expected: All tests PASS

**Step 4: Test user experience manually**

Run: `./platform clean-slate`

Expected: See discovery results displayed:
```
Discovering platform services...
System is already clean! No platform artifacts detected.
```

**Step 5: Commit fixes if any**

```bash
git add <modified-files>
git commit -m "fix: address code review feedback for display output

Task 20c complete - display output reviewed and approved.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Success Criteria

- ✅ All tests passing (420+ including new display tests)
- ✅ Display steps show output to users
- ✅ Message interpolation works correctly
- ✅ MockActionRunner captures display calls
- ✅ RealActionRunner prints to stdout
- ✅ Discovery results now visible in clean-slate wizard
- ✅ No regressions in existing functionality

---

## Execution Notes

- Single-threaded task (no parallel work)
- Should take ~15 minutes to complete all 3 phases
- Focus on minimal implementation (GREEN phase discipline)
- Use superpowers:code-reviewer after GREEN phase
