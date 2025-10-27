# Platform CLI Implementation Checklist - GREEN Phase

## Overview

This checklist guides implementation of the `./platform` CLI wrapper to make all 50 tests pass.

## Implementation Stages

### Stage 1: Create Basic Script Structure

**Goal**: Make basic existence tests pass

- [ ] Create `./platform` file at repository root
- [ ] Add `#!/bin/bash` shebang at top
- [ ] Make script executable (`chmod +x platform`)
- [ ] Run tests: Should see 4/50 tests passing

**Tests to pass**:
- `test_platform_script_exists`
- `test_platform_script_is_file`
- `test_platform_script_is_executable`
- `test_platform_script_has_shebang`

### Stage 2: Add Formatting Library Integration

**Goal**: Source formatting.sh for consistent output

- [ ] Add source line for formatting.sh library
  ```bash
  source "$(dirname "$0")/platform-bootstrap/lib/formatting.sh"
  ```
- [ ] Run tests: Should see formatting integration tests activate

**Tests to pass**:
- `test_setup_sources_formatting_library`
- `test_clean_slate_sources_formatting_library`
- `test_formatting_library_exists` (already passing)

### Stage 3: Implement Subcommand Structure

**Goal**: Recognize setup and clean-slate subcommands

- [ ] Add case statement for subcommand routing
  ```bash
  case "$1" in
      setup) setup_wizard ;;
      clean-slate) clean_slate_wizard ;;
      *)
          echo "Usage: $0 {setup|clean-slate}"
          exit 1
          ;;
  esac
  ```
- [ ] Create empty `setup_wizard()` function
- [ ] Create empty `clean_slate_wizard()` function
- [ ] Run tests: Subcommand recognition tests should pass

**Tests to pass**:
- `test_platform_setup_subcommand_exists`
- `test_platform_clean_slate_subcommand_exists`
- `test_platform_no_subcommand_shows_usage`
- `test_platform_invalid_subcommand_shows_error`

### Stage 4: Implement Setup Wizard Function

**Goal**: Execute setup flow with WizardEngine

- [ ] Add Python code to `setup_wizard()` function
- [ ] Import wizard modules (WizardEngine, RealActionRunner, SpecLoader)
- [ ] Create WizardEngine instance with RealActionRunner
- [ ] Load flows/setup.yaml
- [ ] Register all service validators and actions:
  - [ ] postgres.validate_image_url
  - [ ] postgres.validate_port
  - [ ] postgres.save_config
  - [ ] postgres.init_database
  - [ ] postgres.start_service
  - [ ] openmetadata.validate_image_url
  - [ ] openmetadata.validate_port
  - [ ] openmetadata.save_config
  - [ ] openmetadata.start_service
  - [ ] kerberos.validate_realm
  - [ ] kerberos.validate_kdc
  - [ ] kerberos.save_config
  - [ ] kerberos.init_kerberos
  - [ ] pagila.validate_repo_url
  - [ ] pagila.clone_repo
  - [ ] pagila.load_data
- [ ] Call engine.execute_flow('setup')
- [ ] Add error handling and exit codes
- [ ] Add print_header for "Platform Setup Wizard"
- [ ] Add progress messages using formatting.sh functions

**Example structure**:
```bash
setup_wizard() {
    print_header "Platform Setup Wizard"

    python3 -c "
import sys
from pathlib import Path

# Add wizard to path
sys.path.insert(0, str(Path('.').absolute()))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import RealActionRunner
from wizard.services import postgres, openmetadata, kerberos, pagila

# Create engine
runner = RealActionRunner()
base_path = Path('.') / 'wizard'
engine = WizardEngine(runner=runner, base_path=base_path)

# Register postgres
engine.validators['postgres.validate_image_url'] = postgres.validate_image_url
engine.validators['postgres.validate_port'] = postgres.validate_port
engine.actions['postgres.save_config'] = postgres.save_config
engine.actions['postgres.init_database'] = postgres.init_database
engine.actions['postgres.start_service'] = postgres.start_service

# Register openmetadata
engine.validators['openmetadata.validate_image_url'] = openmetadata.validate_image_url
# ... etc ...

# Execute flow
try:
    engine.execute_flow('setup')
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" || {
    print_error "Setup wizard failed"
    exit 1
}

    print_success "Platform setup completed successfully"
}
```

**Tests to pass**:
- `test_setup_loads_wizard_engine`
- `test_setup_uses_setup_flow_yaml`
- `test_setup_uses_real_action_runner`
- `test_setup_executes_flow`
- `test_setup_handles_user_input`
- `test_setup_saves_platform_config`
- `test_setup_uses_print_header`
- `test_setup_uses_print_check`
- `test_platform_script_imports_wizard_module`
- `test_platform_script_imports_wizard_engine`
- `test_platform_script_imports_real_action_runner`
- `test_platform_script_imports_spec_loader`
- `test_setup_registers_service_modules`
- `test_setup_registers_postgres_validators`
- `test_setup_registers_postgres_actions`
- `test_setup_registers_openmetadata_validators`
- `test_setup_registers_kerberos_validators`
- `test_setup_registers_pagila_validators`

### Stage 5: Implement Clean-Slate Wizard Function

**Goal**: Execute clean-slate flow with WizardEngine

- [ ] Add Python code to `clean_slate_wizard()` function
- [ ] Import wizard modules (same as setup)
- [ ] Create WizardEngine instance with RealActionRunner
- [ ] Load flows/clean-slate.yaml
- [ ] Register teardown actions:
  - [ ] postgres.teardown
  - [ ] openmetadata.teardown
  - [ ] kerberos.teardown
  - [ ] pagila.teardown
- [ ] Call engine.execute_flow('clean-slate')
- [ ] Add print_header with warning about data loss
- [ ] Add teardown progress messages
- [ ] Add error handling and exit codes

**Example structure**:
```bash
clean_slate_wizard() {
    print_header "Platform Clean-Slate"
    print_warning "This will tear down services and may result in data loss"

    python3 -c "
import sys
from pathlib import Path

sys.path.insert(0, str(Path('.').absolute()))

from wizard.engine.engine import WizardEngine
from wizard.engine.runner import RealActionRunner
from wizard.services import postgres, openmetadata, kerberos, pagila

# Create engine
runner = RealActionRunner()
base_path = Path('.') / 'wizard'
engine = WizardEngine(runner=runner, base_path=base_path)

# Register teardown actions
engine.actions['postgres.teardown'] = postgres.teardown
engine.actions['openmetadata.teardown'] = openmetadata.teardown
engine.actions['kerberos.teardown'] = kerberos.teardown
engine.actions['pagila.teardown'] = pagila.teardown

# Execute flow
try:
    engine.execute_flow('clean-slate')
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" || {
    print_error "Clean-slate wizard failed"
    exit 1
}

    print_success "Platform clean-slate completed successfully"
}
```

**Tests to pass**:
- `test_clean_slate_loads_wizard_engine`
- `test_clean_slate_uses_clean_slate_flow_yaml`
- `test_clean_slate_uses_real_action_runner`
- `test_clean_slate_executes_flow`
- `test_clean_slate_handles_user_input`
- `test_clean_slate_uses_print_header`
- `test_clean_slate_registers_teardown_modules`
- `test_clean_slate_displays_warning_header`
- `test_clean_slate_displays_teardown_progress`

### Stage 6: Add Error Handling

**Goal**: Proper exit codes and error messages

- [ ] Add try-catch in Python code blocks
- [ ] Check Python availability before execution
- [ ] Verify flow files exist before loading
- [ ] Show helpful error messages using print_error
- [ ] Exit with code 0 on success
- [ ] Exit with non-zero code on failure

**Example error checking**:
```bash
# Check Python 3 is available
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is required but not found"
    exit 1
fi

# Check wizard module exists
if [ ! -d "wizard" ]; then
    print_error "Wizard module not found at ./wizard"
    exit 1
fi

# Check flow file exists
if [ ! -f "wizard/flows/setup.yaml" ]; then
    print_error "Setup flow file not found at wizard/flows/setup.yaml"
    exit 1
fi
```

**Tests to pass**:
- `test_setup_exits_zero_on_success`
- `test_setup_exits_nonzero_on_error`
- `test_setup_shows_error_message_on_failure`
- `test_setup_handles_python_import_errors`
- `test_setup_handles_missing_flow_files`
- `test_clean_slate_exits_zero_on_success`
- `test_clean_slate_exits_nonzero_on_error`

### Stage 7: Add Output Formatting

**Goal**: User-friendly formatted output

- [ ] Add print_header calls for major sections
- [ ] Add print_section for subsections
- [ ] Add print_step for multi-step processes
- [ ] Add print_check for validation results
- [ ] Add print_success for completion messages
- [ ] Add print_error for error messages
- [ ] Add progress indicators during execution

**Tests to pass**:
- `test_setup_displays_welcome_header`
- `test_setup_displays_service_selection_prompt`
- `test_setup_displays_progress_messages`
- `test_setup_displays_completion_message`

### Stage 8: Add Headless Mode Support

**Goal**: Support non-interactive execution

- [ ] Add --headless flag support
- [ ] Accept headless inputs via environment variables or file
- [ ] Pass headless_inputs to engine.execute_flow()
- [ ] Skip interactive prompts when in headless mode

**Example**:
```bash
HEADLESS_MODE=false
if [ "$2" = "--headless" ]; then
    HEADLESS_MODE=true
fi
```

**Tests to pass**:
- `test_setup_accepts_headless_mode`

## Test Execution Progress Tracking

Run tests frequently to track progress:

```bash
# Run all tests
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py -v

# Run specific stage tests
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py::TestPlatformScriptExists -v
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py::TestSetupFlowIntegration -v

# Watch test count
python3 -m pytest platform-bootstrap/tests/test_platform_cli.py -v | tail -1
```

## Success Criteria

**GREEN Phase Complete When**:
- [ ] All 50 tests passing
- [ ] `./platform setup` successfully runs setup wizard
- [ ] `./platform clean-slate` successfully runs teardown wizard
- [ ] Error handling works correctly
- [ ] Output is well-formatted and user-friendly
- [ ] Platform-config.yaml is created by setup
- [ ] Exit codes are correct (0 for success, non-zero for errors)

## Expected Final Test Output

```
============================== test session starts ==============================
collected 50 items

platform-bootstrap/tests/test_platform_cli.py::TestPlatformScriptExists::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestPlatformScriptSubcommands::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestSetupFlowIntegration::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestCleanSlateFlowIntegration::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestFormattingLibraryIntegration::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestErrorHandling::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestPythonIntegration::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestServiceRegistration::... PASSED
platform-bootstrap/tests/test_platform_cli.py::TestOutputFormatting::... PASSED

============================== 50 passed in 2.5s ===============================
```

## Next Phase: REFACTOR

Once all tests pass:
- Clean up code duplication
- Extract common Python code to helper functions
- Add comments and documentation
- Optimize performance
- Add additional error messages for edge cases
- Consider adding bash completion
- Add --help flag with detailed usage
- Add --version flag
