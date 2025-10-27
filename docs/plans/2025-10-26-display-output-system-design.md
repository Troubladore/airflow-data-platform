# Display Output System Design

**Date:** 2025-10-26
**Status:** Approved for Implementation

## Problem Statement

The wizard engine executes `display` type steps silently - no output shown to users. When running `./platform clean-slate`, users see:

```
════════════════════════════════════════════════════════
  Clean-Slate Wizard
════════════════════════════════════════════════════════

[OK] Clean-slate complete!
```

But discovery results, status messages, and informational prompts are processed silently. Users have no idea what happened.

**Root cause:** Engine has no handling for `display` step type - it silently skips them.

## Solution Overview

Add `display(message)` method to ActionRunner interface. Engine calls `runner.display()` for display steps. RealActionRunner prints to stdout, MockActionRunner captures for testing.

## Design Principles

1. **Keep engine pure/headless** - No print statements in engine
2. **All I/O through runner** - Display output is an external effect
3. **Fully mockable** - Tests can capture and verify display calls
4. **Consistent pattern** - Matches existing runner methods (run_shell, save_config, file_exists)
5. **Message interpolation** - Replace {variable} placeholders with actual state values

## Architecture

### Runner Interface Enhancement

```python
# wizard/engine/runner.py

class ActionRunner(ABC):
    """Abstract interface for all side effects."""

    @abstractmethod
    def display(self, message: str) -> None:
        """Display a message to the user.

        Args:
            message: Text to display (may contain newlines)
        """
        pass

class RealActionRunner(ActionRunner):
    """Production runner - performs actual operations."""

    def display(self, message: str) -> None:
        """Print message to stdout."""
        print(message)

class MockActionRunner(ActionRunner):
    """Test runner - records calls without side effects."""

    def display(self, message: str) -> None:
        """Capture display call for test verification."""
        self.calls.append(('display', message))
```

### Engine Display Handling

```python
# wizard/engine/engine.py - in _execute_step() method

def _execute_step(self, step, headless_inputs):
    """Execute a single step."""

    # Handle display steps
    if step.type == 'display':
        message = self._interpolate_prompt(step.prompt, self.state)
        self.runner.display(message)
        return  # Display steps don't collect input, just show message

    # ... existing action, boolean, string, conditional handling
```

### Message Interpolation

Replace `{variable}` placeholders in prompts with actual state values:

```python
# wizard/engine/engine.py

def _interpolate_prompt(self, prompt: str, state: dict) -> str:
    """Replace {key} placeholders with state values.

    Args:
        prompt: Template string with {placeholders}
        state: Current wizard state

    Returns:
        Interpolated string with values filled in

    Examples:
        prompt: "Found {total_artifacts} artifacts"
        state: {'total_artifacts': 5}
        returns: "Found 5 artifacts"
    """
    import re

    def replacer(match):
        key = match.group(1)
        value = state.get(key, f'{{{key}}}')  # Keep {key} if not found
        return str(value)

    return re.sub(r'\{([^}]+)\}', replacer, prompt)
```

## Example Flow Execution

**YAML spec:**
```yaml
steps:
  - id: show_discovery_results
    type: display
    prompt: |
      Discovering platform services...

      Found {total_artifacts} total artifacts.
    next: check_empty_state
```

**Engine execution:**
1. Loads step with `type: display`
2. Calls `_interpolate_prompt()` to replace `{total_artifacts}` with actual count
3. Calls `runner.display(interpolated_message)`
4. RealActionRunner prints to stdout
5. User sees the message!

**Test verification:**
```python
runner = MockActionRunner()
engine.execute_flow('clean-slate')

# Verify message was displayed
assert ('display', 'Found 0 total artifacts.') in runner.calls
```

## User Experience Improvement

### Before (Silent Execution)
```
════════════════════════════════════════════════════════
  Clean-Slate Wizard
════════════════════════════════════════════════════════

[OK] Clean-slate complete!
```

### After (With Display Output)
```
════════════════════════════════════════════════════════
  Clean-Slate Wizard
════════════════════════════════════════════════════════

Discovering platform services...

PostgreSQL:
  ✓ 0 containers
  ✓ 0 images
  ✓ 0 volumes
  ✓ Config: not found

OpenMetadata:
  ✓ 0 containers
  ✓ 0 images
  ✓ 0 volumes

Kerberos:
  ✓ 0 containers
  ✓ 0 images

Pagila:
  ✓ Repository: not found
  ✓ Database: not found

System is already clean! No platform artifacts detected.

Checked:
  - Docker containers (postgres, openmetadata, kerberos, pagila)
  - Docker images (matching service patterns)
  - Docker volumes (service data)
  - Configuration files (platform-config.yaml, .env files)

[OK] Clean-slate complete!
```

## Testing Strategy

### Unit Tests
- `test_display_method_exists_in_runner` - Interface verification
- `test_real_runner_prints_to_stdout` - RealActionRunner behavior
- `test_mock_runner_captures_display_calls` - MockActionRunner behavior
- `test_interpolate_prompt_replaces_variables` - Interpolation logic
- `test_interpolate_prompt_handles_missing_keys` - Error handling

### Integration Tests
- `test_display_step_calls_runner_display` - Engine integration
- `test_display_step_interpolates_state_values` - End-to-end with state
- `test_clean_slate_shows_discovery_results` - Flow integration
- `test_clean_slate_shows_clean_message_when_empty` - Empty state

## Implementation Plan

### Task 20a: Display Output (RED Phase)
- Write failing tests for `runner.display()` method
- Write failing tests for `_interpolate_prompt()` helper
- Write failing tests for display step execution

### Task 20b: Display Output (GREEN Phase)
- Implement `display()` in ActionRunner, RealActionRunner, MockActionRunner
- Implement `_interpolate_prompt()` in WizardEngine
- Add display step handling to `_execute_step()`

### Task 20c: Display Output (Code Review)
- Review implementation
- Fix any issues
- Verify all tests pass

## Success Criteria

- ✅ Display steps show messages to users
- ✅ Messages interpolate state variables
- ✅ RealActionRunner prints to stdout
- ✅ MockActionRunner captures for testing
- ✅ All existing tests pass (no regressions)
- ✅ Discovery results now visible to users

## Future Enhancements (Out of Scope)

- Formatted display (colors, boxes) via formatting.sh integration
- Progress indicators for long operations
- Conditional display based on verbosity levels
- Display templates for common message patterns

---

**Design Status:** Approved for Implementation
**Next Steps:** Create implementation plan (Phase 6)
