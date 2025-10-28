# Acceptance Testing Guide

## Overview

Acceptance tests verify the wizard works correctly from a **real user's perspective** using interactive terminal simulation.

## Running Tests

### Install Dependencies (UV ONLY!)

```bash
# From repository root
uv sync
```

**NEVER use pip! Always use UV for package management.**

### Run Individual Tests

```bash
# Clean-slate test
python wizard/tests/acceptance/test_clean_slate_pagila.py

# Or use pytest
uv run pytest wizard/tests/acceptance/test_clean_slate_pagila.py::test_clean_slate_interactive -v

# Pagila setup test
uv run pytest wizard/tests/acceptance/test_clean_slate_pagila.py::test_pagila_only_setup -v
```

### Run All Acceptance Tests

```bash
uv run pytest wizard/tests/acceptance/ -v
```

## Test Structure

Each test follows the **Expect-Observe-Evaluate** pattern:

1. **Expect**: What should happen (stated in docstring)
2. **Observe**: Run wizard with pexpect, capture output
3. **Evaluate**: Compare actual vs expected, check UX quality
4. **Report**: PASS/FAIL with evidence

## Writing New Tests

### Composable Test Pattern

```python
def test_scenario_name():
    """
    Expectation: [What you expect to happen]
    """
    # Simulate user interaction
    child = pexpect.spawn('./platform setup', timeout=60, encoding='utf-8')
    child.logfile = open('/tmp/test_output.txt', 'w')

    # Interact with prompts
    child.expect(r'Question\? \[.*\]:')
    child.sendline('answer')

    # Observe results
    output = open('/tmp/test_output.txt').read()
    containers = subprocess.run(['docker', 'ps'], capture_output=True, text=True)

    # Evaluate
    assert 'expected text' in output
    assert 'container-name' in containers.stdout
```

### Test Focus

- **Be specific**: Test one scenario per test function
- **Be composable**: Tests should work independently or together
- **Be realistic**: Simulate actual user workflows
- **Be critical**: Don't let slop through, but be pragmatic

## Troubleshooting

### pexpect not found

```bash
uv sync  # NOT pip install!
```

### Test hangs/timeouts

- Check `/tmp/*_output.txt` for wizard output
- Increase timeout values if needed
- Verify wizard isn't waiting for unexpected input

### Tests pass but wizard broken in practice

- Run wizard manually to verify
- Check that test expectations match reality
- Update tests if wizard behavior intentionally changed

## Philosophy

**Tests should validate what users actually see, not just internal state.**

See `ux_principles.md` for complete UX standards and testing methodology.
