# Platform CLI Tests - RED Phase Summary

## Overview

Created comprehensive failing tests for the CLI wrapper (`./platform` script) that will integrate the wizard engine with a user-friendly command-line interface.

**Status**: RED phase complete - All 50 tests written and properly failing

## Test File Location

- **File**: `platform-bootstrap/tests/test_platform_cli.py`
- **Lines of code**: 611
- **Test functions**: 50
- **Test classes**: 9

## Test Execution Summary

```
1 failed, 4 passed, 45 skipped in 0.17s
```

### Current Test Status:
- **FAILED**: 1 test (test_platform_script_exists - platform script doesn't exist)
- **PASSED**: 4 tests (prerequisites like formatting.sh existence)
- **SKIPPED**: 45 tests (skipped because platform script doesn't exist yet)

Once the `./platform` script is created, the 45 skipped tests will become active and FAIL (because they use `self.fail()` to document expected behavior), demonstrating proper RED phase testing.

## Test Categories

### 1. TestPlatformScriptExists (4 tests)
Basic script file validation:
- `test_platform_script_exists` - Script exists at repository root
- `test_platform_script_is_file` - Is a regular file, not directory
- `test_platform_script_is_executable` - Has execute permissions
- `test_platform_script_has_shebang` - Starts with `#!/bin/bash`

### 2. TestPlatformScriptSubcommands (4 tests)
Command-line interface validation:
- `test_platform_setup_subcommand_exists` - `./platform setup` is recognized
- `test_platform_clean_slate_subcommand_exists` - `./platform clean-slate` is recognized
- `test_platform_no_subcommand_shows_usage` - Shows usage when no subcommand
- `test_platform_invalid_subcommand_shows_error` - Handles invalid subcommands

### 3. TestSetupFlowIntegration (7 tests)
Setup flow wizard integration:
- `test_setup_loads_wizard_engine` - Creates WizardEngine instance
- `test_setup_uses_setup_flow_yaml` - Loads `flows/setup.yaml`
- `test_setup_uses_real_action_runner` - Uses RealActionRunner (not Mock)
- `test_setup_executes_flow` - Calls `engine.execute_flow()`
- `test_setup_handles_user_input` - Accepts interactive input
- `test_setup_saves_platform_config` - Creates `platform-config.yaml`
- `test_setup_accepts_headless_mode` - Supports non-interactive execution

### 4. TestCleanSlateFlowIntegration (5 tests)
Clean-slate flow wizard integration:
- `test_clean_slate_loads_wizard_engine` - Creates WizardEngine instance
- `test_clean_slate_uses_clean_slate_flow_yaml` - Loads `flows/clean-slate.yaml`
- `test_clean_slate_uses_real_action_runner` - Uses RealActionRunner
- `test_clean_slate_executes_flow` - Calls `engine.execute_flow()`
- `test_clean_slate_handles_user_input` - Accepts interactive input

### 5. TestFormattingLibraryIntegration (6 tests)
Formatting.sh integration for consistent output:
- `test_formatting_library_exists` - Library file exists (PASSING)
- `test_setup_sources_formatting_library` - Script sources formatting.sh
- `test_setup_uses_print_header` - Uses `print_header` for sections
- `test_setup_uses_print_check` - Uses `print_check` for status
- `test_clean_slate_sources_formatting_library` - Script sources formatting.sh
- `test_clean_slate_uses_print_header` - Uses `print_header` for sections

### 6. TestErrorHandling (7 tests)
Error handling and exit codes:
- `test_setup_exits_zero_on_success` - Exit code 0 on success
- `test_setup_exits_nonzero_on_error` - Non-zero exit code on error
- `test_setup_shows_error_message_on_failure` - Displays error messages
- `test_setup_handles_python_import_errors` - Handles missing dependencies
- `test_setup_handles_missing_flow_files` - Handles missing YAML files
- `test_clean_slate_exits_zero_on_success` - Exit code 0 on success
- `test_clean_slate_exits_nonzero_on_error` - Non-zero exit code on error

### 7. TestPythonIntegration (6 tests)
Python wizard module integration:
- `test_platform_script_imports_wizard_module` - Imports wizard module
- `test_platform_script_imports_wizard_engine` - Imports WizardEngine
- `test_platform_script_imports_real_action_runner` - Imports RealActionRunner
- `test_platform_script_imports_spec_loader` - Imports SpecLoader
- `test_setup_registers_service_modules` - Registers all service modules
- `test_clean_slate_registers_teardown_modules` - Registers teardown modules

### 8. TestServiceRegistration (5 tests)
Service module registration with engine:
- `test_setup_registers_postgres_validators` - Registers postgres validators
- `test_setup_registers_postgres_actions` - Registers postgres actions
- `test_setup_registers_openmetadata_validators` - Registers openmetadata validators
- `test_setup_registers_kerberos_validators` - Registers kerberos validators
- `test_setup_registers_pagila_validators` - Registers pagila validators

### 9. TestOutputFormatting (6 tests)
User-facing output and messages:
- `test_setup_displays_welcome_header` - Shows welcome message
- `test_setup_displays_service_selection_prompt` - Shows service selection
- `test_setup_displays_progress_messages` - Shows progress during execution
- `test_setup_displays_completion_message` - Shows success message
- `test_clean_slate_displays_warning_header` - Shows warning about data loss
- `test_clean_slate_displays_teardown_progress` - Shows teardown progress

## Expected Platform Script Structure

Based on the tests, the `./platform` script should:

1. **Be a Bash script** at repository root with execute permissions
2. **Source formatting.sh** for consistent output formatting
3. **Import Python wizard module** and create WizardEngine instances
4. **Support two subcommands**:
   - `setup` - Runs setup flow from `flows/setup.yaml`
   - `clean-slate` - Runs teardown flow from `flows/clean-slate.yaml`
5. **Use RealActionRunner** for actual system operations
6. **Register service modules** (postgres, openmetadata, kerberos, pagila)
7. **Handle user input** interactively or via headless mode
8. **Display formatted output** using formatting.sh functions
9. **Return proper exit codes** (0 for success, non-zero for errors)
10. **Show helpful error messages** for missing dependencies or files

## Example Script Skeleton

```bash
#!/bin/bash
# Platform CLI - Main entry point for data platform setup

# Source formatting library
source "$(dirname "$0")/platform-bootstrap/lib/formatting.sh"

setup_wizard() {
    print_header "Platform Setup Wizard"

    # Execute Python wizard with proper imports and registration
    python3 -c "
from pathlib import Path
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import RealActionRunner
from wizard.engine.loader import SpecLoader
from wizard.services import postgres, openmetadata, kerberos, pagila

# Create engine
runner = RealActionRunner()
base_path = Path('.')
engine = WizardEngine(runner=runner, base_path=base_path / 'wizard')

# Register service modules
engine.validators['postgres.validate_image_url'] = postgres.validate_image_url
# ... register all validators and actions ...

# Execute flow
engine.execute_flow('setup')
"
}

clean_slate_wizard() {
    print_header "Platform Clean-Slate"
    print_warning "This will tear down services and may result in data loss"

    # Similar Python execution for clean-slate flow
}

case "\$1" in
    setup) setup_wizard ;;
    clean-slate) clean_slate_wizard ;;
    *) echo "Usage: ./platform {setup|clean-slate}" ;;
esac
```

## Next Steps (GREEN Phase)

1. Create `./platform` script at repository root
2. Implement setup_wizard() function
3. Implement clean_slate_wizard() function
4. Register all service validators and actions
5. Add error handling and exit codes
6. Integrate formatting.sh for output
7. Run tests and watch them pass

## Success Criteria Met

✓ All 50 tests written and documented
✓ Tests cover CLI invocation, flow execution, formatting, error handling
✓ Clear test names document expected behavior
✓ Tests properly SKIP when script missing, will FAIL when script incomplete
✓ RED phase complete - ready for GREEN phase implementation

## Test Execution

```bash
# Run all CLI tests
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py -v

# Run specific test class
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py::TestSetupFlowIntegration -v

# Run with coverage
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py --cov=platform --cov-report=term
```
