# Platform Bootstrap Testing Framework

## Overview

This directory contains comprehensive testing tools to ensure all platform bootstrap scripts are reliable and demo-safe. The testing framework prevents common failures like syntax errors, missing dependencies, and formatting issues.

## Key Components

### 1. Dry-Run Test Suite (`dry-run-all-scripts.sh`)

Comprehensive test suite that validates all critical scripts without executing dangerous operations.

**Features:**
- Syntax validation for all shell scripts
- Help/version output testing
- Color code and Unicode character validation
- Interactive script safety testing
- Critical path simulation

**Usage:**
```bash
./tests/dry-run-all-scripts.sh
```

### 2. Shell Syntax Validator (`test-shell-syntax.sh`)

Deep syntax validation for shell scripts, checking for:
- Basic bash syntax errors
- Unclosed quotes
- Missing `fi`, `done`, `esac` statements
- `local` used outside functions
- If/fi mismatches

**Usage:**
```bash
./tests/test-shell-syntax.sh
```

### 3. Pre-Push Git Hook (`.githooks/pre-push`)

Automatically runs validation tests before allowing pushes to remote repository.

**Setup:**
```bash
./setup-hooks.sh
```

## Shared Formatting Library

The `lib/formatting.sh` library provides consistent output formatting across all scripts:

- **Automatic terminal detection** - Uses colors/Unicode in terminals, plain ASCII otherwise
- **NO_COLOR support** - Respects the standard NO_COLOR environment variable
- **DRY principle** - No duplicated formatting code across scripts
- **Rich formatting functions**:
  - `print_header()` - Section headers
  - `print_check()` - Status checks with PASS/FAIL/WARN/INFO
  - `print_bullet()` - Bullet point lists
  - `print_arrow()` - Arrow indicators
  - `print_status()` - Status messages with checkmarks
  - `print_env_var()` - Environment variable display

## Test Categories

### Syntax Validation
- Checks all scripts compile without errors
- Catches missing quotes, brackets, etc.
- Prevents embarrassing syntax errors during demos

### Execution Tests
- Tests scripts can run without crashing
- Validates help output works
- Ensures quick/dry-run modes function

### Formatting Tests
- Ensures NO_COLOR is respected
- Validates no Unicode leaks to non-terminals
- Checks color codes are properly handled

### Interactive Safety
- Tests scripts handle non-interactive mode
- Validates 'no' responses exit cleanly
- Ensures no infinite loops or hangs

## Running Tests

### Run All Tests
```bash
./tests/dry-run-all-scripts.sh
```

### Run Specific Test Categories
```bash
# Just syntax checks
./tests/test-shell-syntax.sh

# Test a specific script
bash -n ../script-name.sh  # Syntax only
NO_COLOR=1 ../script-name.sh --help  # Test NO_COLOR
```

### Test Output Examples

**Success:**
```
✅ ALL DRY RUN TESTS PASSED

All scripts can execute without crashing.
Safe to demo and ship!
```

**Failure:**
```
❌ DRY RUN FAILED - THESE WILL BREAK IN DEMOS!

Failed tests:
  - script-name.sh: Description

DO NOT SHIP THIS CODE!
Fix these issues before creating a PR.
```

## Environment Variables

- `NO_COLOR=1` - Disable colors and Unicode in output
- `DRY_RUN=1` - Signal to scripts they're being tested

## Adding New Scripts to Testing

To add a new script to the test suite:

1. Add to `SCRIPTS_TO_TEST` array in `dry-run-all-scripts.sh`
2. Add appropriate test based on script type:
   - Interactive scripts: Test with piped input
   - Diagnostic scripts: Test with `-q` or `--help`
   - Setup scripts: Test with `bash -n` syntax check

Example:
```bash
# Add to SCRIPTS_TO_TEST array
SCRIPTS_TO_TEST=(
    # ... existing scripts ...
    "my-new-script.sh"
)

# Add appropriate test
test_script "my-new-script.sh" "./my-new-script.sh --help" "Help output"
```

## Best Practices

1. **Always use the formatting library** - Source `lib/formatting.sh` in new scripts
2. **Test before committing** - Run `./tests/dry-run-all-scripts.sh`
3. **Keep tests fast** - Use timeouts and quick modes
4. **Test edge cases** - Empty input, missing files, no permissions

## Troubleshooting

### Test Failures

If a test fails:
1. Run the test directly to see detailed output
2. Check for syntax errors with `bash -n script.sh`
3. Test with `NO_COLOR=1` to check formatting
4. Ensure script has proper error handling

### Hook Issues

If pre-push hook isn't working:
1. Check hook is executable: `ls -l .githooks/pre-push`
2. Verify git config: `git config core.hooksPath`
3. Re-run setup: `./setup-hooks.sh`

## Continuous Improvement

The test suite should grow with the codebase:
- Add tests for new scripts
- Add checks for new failure modes
- Update formatting library with new patterns
- Keep tests maintainable and fast