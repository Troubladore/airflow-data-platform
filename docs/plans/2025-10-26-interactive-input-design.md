# Interactive Input System Design

**Date:** 2025-10-26
**Status:** Approved for Implementation

## Problem Statement

The wizard displays prompts but doesn't wait for user input. It immediately proceeds with empty/default values, making it appear broken to users.

**Current behavior:**
```bash
$ ./platform setup
PostgreSQL image [{current_value}]:
Use prebuilt image? (y/n):
PostgreSQL password:
✓ Setup complete!
# User never got to type anything!
```

**Root cause:** Engine only implements headless mode (pre-provided answers via `headless_inputs` dict). There's no code to read from stdin interactively.

**Why our 428 tests didn't catch this:** All tests use `headless_inputs` - we never tested actual interactive input collection.

## Solution Overview

Add `get_input(prompt, default)` method to ActionRunner interface. Engine tracks whether it's in headless or interactive mode. When interactive, engine calls `runner.get_input()` to read from stdin. When headless, uses `headless_inputs` dict.

## Design Principles

1. **Interactive by default** - Real users need interactive, headless is for testing only
2. **Explicit headless flag** - Presence of `headless_inputs` parameter indicates test mode
3. **Runner abstraction** - All I/O through runner interface (including stdin)
4. **Validation feedback loop** - Re-prompt on invalid input (interactive only)
5. **Backward compatible** - All existing tests continue to work unchanged

## Architecture

### Runner Interface Enhancement

```python
# wizard/engine/runner.py

class ActionRunner(ABC):
    """Abstract interface for all side effects."""

    @abstractmethod
    def get_input(self, prompt: str, default: str = None) -> str:
        """Get input from user.

        Args:
            prompt: Question to ask
            default: Default value shown in [brackets], returned if user presses Enter

        Returns:
            User's input string (or default if empty)
        """
        pass


class RealActionRunner(ActionRunner):
    """Production runner - performs actual I/O."""

    def get_input(self, prompt: str, default: str = None) -> str:
        """Read from stdin with optional default."""
        if default:
            # Show default in prompt
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

    def get_input(self, prompt: str, default: str = None) -> str:
        """Return next value from input_queue."""
        self.calls.append(('get_input', prompt, default))

        # Return next scripted response
        if self.input_queue:
            return self.input_queue.pop(0)

        # Fall back to default if no scripted response
        return default if default else ''
```

### Engine Mode Detection

```python
# wizard/engine/engine.py

class WizardEngine:
    def execute_flow(self, flow_name: str, headless_inputs: Optional[Dict] = None):
        """Execute a flow.

        Args:
            flow_name: Flow to execute (setup, clean-slate)
            headless_inputs: Optional dict of pre-provided answers
                            If None: INTERACTIVE mode (read from stdin)
                            If provided: HEADLESS mode (use dict, for testing)
        """
        # Determine mode
        self.headless_mode = (headless_inputs is not None)
        self.headless_inputs = headless_inputs or {}

        # ... rest of flow execution
```

### Input Collection Logic

```python
# wizard/engine/engine.py - in _execute_step()

def _execute_step(self, step, headless_inputs):
    """Execute a single step."""

    # Display steps (already working)
    if step.type == 'display':
        if step.prompt:
            message = self._interpolate_prompt(step.prompt, self.state)
            self.runner.display(message)
        return

    # Display prompt for interactive steps
    if step.prompt and step.type in ['string', 'boolean', 'integer', 'enum']:
        prompt_text = self._interpolate_prompt(step.prompt, self.state)
        self.runner.display(prompt_text)

    # Collect input
    if step.type in ['string', 'boolean', 'integer', 'enum']:
        user_input = self._get_validated_input(step)

        # Store in state
        if step.state_key:
            self.state[step.state_key] = user_input

        return  # Input collected

    # ... rest of step types


def _get_validated_input(self, step) -> Any:
    """Get and validate user input with retry loop."""

    while True:
        # Get input based on mode
        if self.headless_mode:
            # Use pre-provided answer
            user_input = self.headless_inputs.get(step.id, step.default_value or '')
        else:
            # Ask user interactively
            default = step.default_value
            if step.default_from:
                default = self.state.get(step.default_from, default)

            user_input = self.runner.get_input(step.prompt, default)

        # Validate
        if step.validator:
            try:
                validated = self._run_validator(step.validator, user_input, self.state)
                return validated  # Success!
            except ValueError as e:
                if self.headless_mode:
                    raise  # Fail fast in tests
                else:
                    # Show error and re-prompt
                    self.runner.display(f"Error: {e}")
                    continue  # Loop back
        else:
            return user_input  # No validation needed
```

### Testing Strategy

**Headless Mode Tests (existing 428 tests):**
```python
# No changes needed - all existing tests continue to work
engine.execute_flow('setup', headless_inputs={'postgres_image': 'custom'})
```

**Interactive Mode Tests (new):**
```python
# Test interactive input collection
runner = MockActionRunner()
runner.input_queue = ['postgres:17.5', 'n', 'md5', 'password123', '5432']

engine = WizardEngine(runner=runner, base_path='wizard')
engine.execute_flow('setup')  # No headless_inputs = interactive!

# Verify correct prompts shown
assert ('get_input', 'PostgreSQL image:', 'postgres:17.5-alpine') in runner.calls

# Verify inputs were used
assert engine.state['services.postgres.image'] == 'postgres:17.5'
```

**Validation Loop Tests:**
```python
# Test re-prompting on invalid input
runner = MockActionRunner()
runner.input_queue = [
    '999999',  # Invalid port
    'abc',     # Invalid port
    '5433'     # Valid port
]

engine = WizardEngine(runner=runner, base_path='wizard')
# Should show 2 error messages before accepting valid input
```

Does this testing approach look good?