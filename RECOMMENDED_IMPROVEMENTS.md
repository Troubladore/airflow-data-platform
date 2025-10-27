# Recommended Improvements: Service Selection Polish

This document provides code snippets for implementing the polish improvements identified during BAT.

---

## Issue 1: Service Name Validation (Priority: Medium)

### Current Behavior
- User types invalid service name (typo or wrong case)
- Wizard continues without error
- Service isn't installed
- User discovers problem after installation completes

### Proposed Solution
Validate service names against available options and show clear error message.

### Code Changes

**File:** `/home/troubladore/repos/airflow-data-platform/.worktrees/data-driven-wizard/wizard/engine/engine.py`

**Location:** Line ~439 in `execute_flow()` method

**Current code:**
```python
# Get input with prompt from YAML spec
prompt_text = self._interpolate_prompt(step.prompt, self.state) if step.prompt else "Enter services"
response = self.runner.get_input(prompt_text, '')

# Parse space-separated list
if response:
    selected = [s.strip() for s in response.split() if s.strip()]
else:
    selected = []
```

**Improved code:**
```python
# Get input with prompt from YAML spec
prompt_text = self._interpolate_prompt(step.prompt, self.state) if step.prompt else "Enter services"

# Build list of valid service names from options
valid_services = [opt.get('value', '') for opt in step.options] if step.options else []

while True:  # Validation loop
    response = self.runner.get_input(prompt_text, '')

    # Parse space-separated list
    if response:
        selected = [s.strip() for s in response.split() if s.strip()]
    else:
        selected = []

    # Validate service names
    if selected:
        invalid_services = [s for s in selected if s not in valid_services]

        if invalid_services:
            # Show error message
            self.runner.display(f"\nError: Unknown service(s): {', '.join(invalid_services)}")
            self.runner.display(f"Valid options: {', '.join(valid_services)}")
            self.runner.display("")

            # In headless mode, fail fast
            if self.headless_mode:
                raise ValueError(f"Invalid service names: {invalid_services}")

            # In interactive mode, re-prompt
            continue

    # Validation passed, exit loop
    break
```

**Benefits:**
- Catches typos immediately
- Prevents silent failures
- Shows user what went wrong
- Lists valid options as reminder
- Maintains headless test behavior (fail fast)

**Testing:**
```python
# Test case 1: Valid input
runner.input_queue = ['openmetadata kerberos', '', '', '', '', '']
engine.execute_flow('setup')
# Should work without error

# Test case 2: Invalid input (should re-prompt in interactive)
runner.input_queue = ['openmedata', 'openmetadata', '', '', '', '', '']
#                      ↑ typo       ↑ corrected after error
engine.execute_flow('setup')
# Should show error and re-prompt

# Test case 3: Headless mode should fail fast
runner.input_queue = ['invalid_service', '', '', '', '', '']
with pytest.raises(ValueError, match="Invalid service names"):
    engine.execute_flow('setup')
```

---

## Issue 2: Comma Separation Support (Priority: Low)

### Current Behavior
- User types `openmetadata,kerberos` (comma-separated)
- Parser treats entire string as one service name
- Service name doesn't match any option
- Nothing gets installed (silent failure)

### Proposed Solution
Support both space and comma separation for user convenience.

### Code Changes

**File:** `/home/troubladore/repos/airflow-data-platform/.worktrees/data-driven-wizard/wizard/engine/engine.py`

**Location:** Line ~439 in `execute_flow()` method

**Current code:**
```python
# Parse space-separated list
if response:
    selected = [s.strip() for s in response.split() if s.strip()]
else:
    selected = []
```

**Improved code:**
```python
# Parse space-separated or comma-separated list
if response:
    # Replace commas with spaces to support both formats
    response = response.replace(',', ' ')
    selected = [s.strip() for s in response.split() if s.strip()]
else:
    selected = []
```

**Benefits:**
- More forgiving parser
- Supports intuitive comma format
- No change to space-separated format
- Simple one-line fix

**Testing:**
```python
# Test case 1: Space-separated (original)
runner.input_queue = ['openmetadata kerberos', '', '', '', '', '']
engine.execute_flow('setup')
assert engine.state.get('services.openmetadata.enabled') == True
assert engine.state.get('services.kerberos.enabled') == True

# Test case 2: Comma-separated (new)
runner.input_queue = ['openmetadata,kerberos', '', '', '', '', '']
engine.execute_flow('setup')
assert engine.state.get('services.openmetadata.enabled') == True
assert engine.state.get('services.kerberos.enabled') == True

# Test case 3: Mixed format
runner.input_queue = ['openmetadata, kerberos pagila', '', '', '', '', '']
engine.execute_flow('setup')
assert engine.state.get('services.openmetadata.enabled') == True
assert engine.state.get('services.kerberos.enabled') == True
assert engine.state.get('services.pagila.enabled') == True
```

---

## Issue 3: Confirmation Display (Priority: Low, Optional)

### Current Behavior
- User types service names
- Wizard immediately proceeds to configuration
- No confirmation of what will be installed

### Proposed Solution
Show confirmation of selected services before proceeding.

### Code Changes

**File:** `/home/troubladore/repos/airflow-data-platform/.worktrees/data-driven-wizard/wizard/engine/engine.py`

**Location:** After service selection parsing, before state update

**Add this code:**
```python
# After parsing selected services
if selected:
    # Show confirmation
    self.runner.display("\nYou selected:")
    for service_name in selected:
        # Find the option to show full label
        option_label = None
        for opt in step.options:
            if opt.get('value') == service_name:
                option_label = opt.get('label', '')
                break

        if option_label:
            self.runner.display(f"  ✓ {service_name} ({option_label})")
        else:
            self.runner.display(f"  ✓ {service_name}")

    # Always include postgres
    self.runner.display(f"  ✓ postgres (PostgreSQL database - always included)")
    self.runner.display("")

    # Optional: Ask for confirmation (uncomment to require confirmation)
    # confirm = self.runner.get_input("Continue with these services? (y/n)", "y")
    # if confirm.lower() != 'y':
    #     # User wants to change selection
    #     continue  # If in validation loop
```

**Benefits:**
- User sees exactly what will be installed
- Catches mistakes before installation starts
- Optional confirmation step
- Reminds user that postgres is always included

**Alternative: Non-Interactive Confirmation**
If you don't want to add another prompt, just show the summary:

```python
if selected:
    self.runner.display("\nServices to be installed:")
    for service_name in selected:
        option_label = next(
            (opt.get('label', '') for opt in step.options if opt.get('value') == service_name),
            ''
        )
        self.runner.display(f"  • {service_name}" + (f" - {option_label}" if option_label else ""))
    self.runner.display(f"  • postgres - PostgreSQL database (always included)")
    self.runner.display("")
```

---

## Combined Implementation

Here's how all three improvements work together:

```python
# In wizard/engine/engine.py, execute_flow() method
# Around line 435-442

if step.type == 'multi_select':
    # Display available options
    if step.options:
        self.runner.display("")  # Blank line before options
        for option in step.options:
            value = option.get('value', '')
            label = option.get('label', '')
            self.runner.display(f"  - {value}: {label}")
        self.runner.display("")  # Blank line after options

    # Get input with validation loop
    prompt_text = self._interpolate_prompt(step.prompt, self.state) if step.prompt else "Enter services"
    valid_services = [opt.get('value', '') for opt in step.options] if step.options else []

    while True:  # Validation loop
        response = self.runner.get_input(prompt_text, '')

        # Parse with comma support (Issue 2)
        if response:
            response = response.replace(',', ' ')  # Support commas
            selected = [s.strip() for s in response.split() if s.strip()]
        else:
            selected = []

        # Validate service names (Issue 1)
        if selected:
            invalid_services = [s for s in selected if s not in valid_services]

            if invalid_services:
                self.runner.display(f"\nError: Unknown service(s): {', '.join(invalid_services)}")
                self.runner.display(f"Valid options: {', '.join(valid_services)}")
                self.runner.display("")

                if self.headless_mode:
                    raise ValueError(f"Invalid service names: {invalid_services}")

                continue  # Re-prompt

        # Show confirmation (Issue 3)
        if selected:
            self.runner.display("\nSelected services:")
            for service_name in selected:
                option_label = next(
                    (opt.get('label', '') for opt in step.options if opt.get('value') == service_name),
                    ''
                )
                self.runner.display(f"  ✓ {service_name}" + (f" - {option_label}" if option_label else ""))
            self.runner.display(f"  ✓ postgres (always included)")
            self.runner.display("")

        # Validation passed, exit loop
        break
```

---

## Testing Checklist

After implementing improvements, verify:

- [ ] Valid inputs still work (no regression)
  ```python
  runner.input_queue = ['openmetadata', '', '', '', '', '']
  engine.execute_flow('setup')
  assert engine.state.get('services.openmetadata.enabled') == True
  ```

- [ ] Invalid inputs show error and re-prompt
  ```python
  runner.input_queue = ['invalid', 'openmetadata', '', '', '', '', '']
  engine.execute_flow('setup')
  # Should prompt twice, second time succeeds
  ```

- [ ] Comma separation works
  ```python
  runner.input_queue = ['openmetadata,kerberos', '', '', '', '', '']
  engine.execute_flow('setup')
  assert engine.state.get('services.openmetadata.enabled') == True
  assert engine.state.get('services.kerberos.enabled') == True
  ```

- [ ] Empty input still works (postgres only)
  ```python
  runner.input_queue = ['', '', '', '', '', '']
  engine.execute_flow('setup')
  assert engine.state.get('services.postgres.enabled') == True
  assert engine.state.get('services.openmetadata.enabled') == False
  ```

- [ ] Headless mode fails fast on invalid input
  ```python
  with pytest.raises(ValueError):
      runner.input_queue = ['invalid_name', '', '', '', '', '']
      engine.execute_flow('setup')
  ```

- [ ] Existing unit tests still pass
  ```bash
  pytest wizard/tests/test_service_selection_interactive.py -v
  ```

- [ ] BAT tests pass with improvements
  ```bash
  python test_bat_service_selection.py
  ```

---

## Effort Estimation

| Improvement | Lines of Code | Complexity | Test Changes | Estimated Time |
|-------------|---------------|------------|--------------|----------------|
| Issue 1: Validation | ~15 lines | Low-Medium | Add 2-3 tests | 30-45 minutes |
| Issue 2: Comma support | ~1 line | Very Low | Add 2 tests | 10 minutes |
| Issue 3: Confirmation | ~10 lines | Low | Add 1 test | 20 minutes |
| **Total** | ~26 lines | Low-Medium | 5-6 tests | **60-75 minutes** |

---

## Priority Recommendation

If implementing incrementally:

1. **Phase 1 (Quick win):** Issue 2 - Comma support
   - Simplest change (1 line)
   - Immediate UX improvement
   - Low risk

2. **Phase 2 (High value):** Issue 1 - Validation
   - Prevents silent failures
   - Biggest UX improvement
   - Moderate complexity

3. **Phase 3 (Nice polish):** Issue 3 - Confirmation
   - Final polish step
   - Lower priority
   - Can wait for user feedback

---

## Roll-Back Plan

If issues arise after deployment:

1. **Validation causing problems?**
   - Remove validation loop
   - Keep `valid_services` list
   - Just log invalid names instead of blocking

2. **Comma support breaking something?**
   - Remove the `replace(',', ' ')` line
   - Update user guide to emphasize "spaces only"

3. **Confirmation too chatty?**
   - Make it conditional: `if len(selected) > 1:`
   - Or remove entirely and keep simple flow

---

## Questions?

- **Should validation block in interactive mode?**
  Recommendation: Yes, re-prompt for correct input
  Alternative: Continue with valid services only, warn about invalid

- **Should comma support handle edge cases like trailing commas?**
  Current approach: Yes, `split()` handles this naturally
  Example: `"a,b,"` becomes `['a', 'b']` (empty strings filtered)

- **Should confirmation require explicit Yes/No?**
  Recommendation: No, just display summary
  Alternative: Add `get_input("Continue? (y/n)", "y")` if desired
