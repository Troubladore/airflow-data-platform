# Service Selection Interactive Mode Fix - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix service selection to work in interactive mode by calling get_input() for multi_select steps instead of only reading from headless_inputs dict.

**Architecture:** Service selection currently only works in headless mode (lines 415-438 in engine.py check `if step.id in headless_inputs`). Need to add interactive path that calls runner.get_input() for multi_select steps and parses space-separated service list.

**Tech Stack:** Python 3.12, existing wizard architecture

---

## Root Cause Analysis

**Current code (engine.py:413-438):**
```python
if flow.service_selection:
    for step in flow.service_selection:
        if step.id in (headless_inputs or {}):  # ← ONLY works in headless mode!
            selected = headless_inputs[step.id]
            # ... update service flags
```

**Problem:** When `headless_inputs` is None (interactive mode), this entire block is skipped. Service selection never happens, so all services remain disabled (except postgres which is always enabled).

**Impact:** In interactive mode, the wizard skips service selection and goes straight to postgres configuration. Users can't select openmetadata, kerberos, or pagila.

---

## Task 23a: Service Selection Interactive (RED Phase)

**Files:**
- Create: `wizard/tests/test_service_selection_interactive.py`

**Step 1: Write failing test for interactive service selection**

Create `wizard/tests/test_service_selection_interactive.py`:

```python
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
```

**Step 2: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_service_selection_interactive.py -v`

Expected: FAIL (service selection not implemented for interactive mode)

**Step 3: Commit**

```bash
git add wizard/tests/test_service_selection_interactive.py
git commit -m "feat: add service selection interactive tests (RED phase)

Task 23a - tests for interactive service selection.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 23b: Service Selection Interactive (GREEN Phase)

**Files:**
- Modify: `wizard/engine/engine.py:413-438`

**Step 1: Implement interactive service selection**

Replace the service_selection block in `wizard/engine/engine.py`:

```python
        # Execute service selection steps
        if flow.service_selection:
            for step in flow.service_selection:
                # Get service selection (headless or interactive)
                if self.headless_mode:
                    # Use pre-provided selection from dict
                    if step.id in self.headless_inputs:
                        selected = self.headless_inputs[step.id]
                    else:
                        selected = []
                else:
                    # Ask user interactively for multi_select
                    if step.type == 'multi_select':
                        # Display prompt
                        if step.prompt:
                            prompt_text = self._interpolate_prompt(step.prompt, self.state)
                            self.runner.display(prompt_text)

                        # Get input
                        response = self.runner.get_input(step.prompt, '')

                        # Parse space-separated list
                        if response:
                            selected = [s.strip() for s in response.split() if s.strip()]
                        else:
                            selected = []
                    else:
                        # Other selection types not implemented yet
                        selected = []

                # Store selected services
                if step.state_key:
                    self.state[step.state_key] = selected

                # Update service enabled flags based on selection
                for target in flow.targets:
                    service_name = target['service']

                    if is_teardown_flow:
                        # For teardown, services are enabled if explicitly selected
                        if service_name in selected:
                            self.state[f'services.{service_name}.teardown.enabled'] = True
                        else:
                            self.state[f'services.{service_name}.teardown.enabled'] = False
                    else:
                        # For setup, postgres always enabled, others based on selection
                        if service_name == 'postgres':
                            self.state[f'services.{service_name}.enabled'] = True
                        elif service_name in selected:
                            self.state[f'services.{service_name}.enabled'] = True
                        else:
                            self.state[f'services.{service_name}.enabled'] = False
```

**Step 2: Run tests to verify they pass**

Run: `uv run pytest wizard/tests/test_service_selection_interactive.py -v`

Expected: 4 tests PASS

**Step 3: Run acceptance tests**

Run: `uv run pytest wizard/tests/test_setup_acceptance.py -v`

Expected: All 4 tests PASS

**Step 4: Run full test suite**

Run: `uv run pytest wizard/ platform-bootstrap/tests/ -q`

Expected: All tests PASS (444+)

**Step 5: Commit**

```bash
git add wizard/engine/engine.py
git commit -m "feat: implement service selection for interactive mode (GREEN phase)

Task 23b - service selection now works interactively!

Users can select services by typing space-separated names.
Example: 'openmetadata kerberos' or press Enter for none.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com)"
```

---

## Task 23c: Service Selection Code Review

**Step 1: Run code review**

Use superpowers:code-reviewer.

**Step 2: Run acceptance testing**

Use business analyst perspective to test:
```bash
./platform setup
# At service selection, type: openmetadata kerberos
# Should configure postgres, openmetadata, kerberos
```

**Step 3: Fix any issues**

**Step 4: Commit fixes if any**

---

## Success Criteria

- ✅ Service selection prompts user in interactive mode
- ✅ Space-separated service list parsed correctly
- ✅ Selected services are enabled
- ✅ Unselected services remain disabled
- ✅ Postgres always enabled (regardless of selection)
- ✅ Empty selection works (postgres only)
- ✅ All 444+ tests passing

---

## Expected User Experience After Fix

```bash
$ ./platform setup

════════════════════════════════════════════════════════
  Platform Setup Wizard
════════════════════════════════════════════════════════

Select services to install (space-separated):
  - openmetadata: OpenMetadata - Data catalog
  - kerberos: Kerberos - Authentication
  - pagila: Pagila - Sample database

Enter services to install: openmetadata kerberos

────────────────────────────────────────────────────────
PostgreSQL Configuration
────────────────────────────────────────────────────────

PostgreSQL image [postgres:17.5-alpine]:
Use prebuilt image? [n]:
...

────────────────────────────────────────────────────────
OpenMetadata Configuration
────────────────────────────────────────────────────────

OpenMetadata server image [openmetadata/server:1.3.0]:
...
```
