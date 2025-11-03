"""Tests for Pagila actions - RED phase"""
import pytest
from wizard.engine.runner import MockActionRunner
from wizard.services.pagila.actions import (
    save_config,
    install_pagila,
    check_postgres_dependency
)


def test_save_config_stores_repo_url():
    """save_config should store the Pagila repository URL in config"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git',
        'services.pagila.enabled': True
    }

    save_config(ctx, mock_runner)

    # Assert runner.save_config was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'

    # Assert pagila config is in the saved data
    config = mock_runner.calls[0][1]
    assert 'services' in config
    assert 'pagila' in config['services']
    assert config['services']['pagila']['enabled'] is True
    assert config['services']['pagila']['repo_url'] == 'https://github.com/devrimgunduz/pagila.git'


def test_save_config_includes_path():
    """save_config should save to platform-config.yaml"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git',
        'services.pagila.enabled': True
    }

    save_config(ctx, mock_runner)

    # Assert saved to correct path
    assert mock_runner.calls[0][2] == 'platform-config.yaml'


def test_install_pagila_calls_setup_script():
    """install_pagila should call the Pagila setup script via runner"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git'
    }

    install_pagila(ctx, mock_runner)

    # Assert runner.run_shell was called with setup script
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1
    assert run_shell_calls[0][0] == 'run_shell'

    # Assert command includes pagila setup
    command = run_shell_calls[0][1]
    assert 'pagila' in ' '.join(command).lower()


def test_install_pagila_passes_repo_url():
    """install_pagila should pass repository URL to setup script"""
    mock_runner = MockActionRunner()
    repo_url = 'https://github.com/devrimgunduz/pagila.git'
    ctx = {
        'services.pagila.repo_url': repo_url
    }

    install_pagila(ctx, mock_runner)

    # Assert repo URL is in the command or environment
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)
    # Updated to check for PAGILA_REPO_URL (the correct variable name)
    assert repo_url in command_str or 'PAGILA_REPO_URL' in command_str


def test_install_pagila_uses_correct_variable_name():
    """install_pagila must use PAGILA_REPO_URL (not PAGILA_REPO) to match setup script"""
    mock_runner = MockActionRunner()
    repo_url = 'https://github.com/devrimgunduz/pagila.git'
    ctx = {
        'services.pagila.repo_url': repo_url
    }

    install_pagila(ctx, mock_runner)

    # The setup-pagila.sh script expects PAGILA_REPO_URL environment variable
    # This test ensures we pass the correct variable name
    # Filter for run_shell calls only (ignore display calls)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) > 0, "No shell command was executed"

    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    # Must contain PAGILA_REPO_URL= (not just PAGILA_REPO=)
    assert 'PAGILA_REPO_URL=' in command_str, \
        f"Command must use PAGILA_REPO_URL variable, got: {command_str}"


def test_install_pagila_uses_make_target():
    """install_pagila should use make target for consistency"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git'
    }

    install_pagila(ctx, mock_runner)

    # Assert make command is used
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    assert 'make' in command or 'Makefile' in ' '.join(command)


def test_check_postgres_dependency_success():
    """check_postgres_dependency should return True if postgres is available"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.base_platform.postgres.enabled': True,
        'services.base_platform.postgres.port': 5432
    }

    result = check_postgres_dependency(ctx, mock_runner)

    assert result is True


def test_check_postgres_dependency_failure_not_enabled():
    """check_postgres_dependency should return False if postgres not enabled"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.base_platform.postgres.enabled': False
    }

    result = check_postgres_dependency(ctx, mock_runner)

    assert result is False


def test_check_postgres_dependency_failure_missing():
    """check_postgres_dependency should return False if postgres config missing"""
    mock_runner = MockActionRunner()
    ctx = {}

    result = check_postgres_dependency(ctx, mock_runner)

    assert result is False


def test_check_postgres_dependency_checks_connection():
    """check_postgres_dependency should verify postgres is actually running"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {
        'stdout': 'PostgreSQL 17.5',
        'stderr': '',
        'returncode': 0
    }
    ctx = {
        'services.base_platform.postgres.enabled': True,
        'services.base_platform.postgres.port': 5432
    }

    result = check_postgres_dependency(ctx, mock_runner)

    # Assert it tried to check postgres connection
    assert len(mock_runner.calls) >= 1
    assert result is True


# ============================================================================
# INTERFACE COMPLIANCE TESTS - RED PHASE
# ============================================================================

def test_save_config_signature_matches_interface():
    """Action must accept (ctx, runner) signature."""
    import inspect
    sig = inspect.signature(save_config)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_actions_use_runner_not_direct_io():
    """All actions must use runner interface, not direct I/O."""
    mock_runner = MockActionRunner()
    ctx = {'services.pagila.repo_url': 'https://github.com/user/repo.git'}

    save_config(ctx, mock_runner)

    # Verify runner was used
    assert len(mock_runner.calls) > 0
    assert mock_runner.calls[0][0] == 'save_config'


# ============================================================================
# PAGILA POSTGRESQL IMAGE TESTS - RED PHASE
# ============================================================================

def test_save_config_includes_postgres_image():
    """save_config should store the Pagila PostgreSQL image in config"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.enabled': True,
        'services.pagila.postgres_image': 'postgres:17.5-alpine'
    }

    save_config(ctx, mock_runner)

    # Assert config includes postgres_image
    config = mock_runner.calls[0][1]
    assert 'services' in config
    assert 'pagila' in config['services']
    assert config['services']['pagila']['postgres_image'] == 'postgres:17.5-alpine'


def test_save_config_postgres_image_defaults_to_platform():
    """save_config should default Pagila's image to match platform postgres"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.enabled': True,
        'services.base_platform.postgres.image': 'artifactory.company.com/postgres:17.5',
        # Note: services.pagila.postgres_image not set - should default to platform
    }

    save_config(ctx, mock_runner)

    # Assert Pagila inherits platform image when not explicitly set
    config = mock_runner.calls[0][1]
    assert config['services']['pagila']['postgres_image'] == 'artifactory.company.com/postgres:17.5'


def test_install_pagila_passes_postgres_image():
    """install_pagila should pass IMAGE_POSTGRES to setup script"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.postgres_image': 'artifactory.company.com/postgres:17.5'
    }

    install_pagila(ctx, mock_runner)

    # Assert IMAGE_POSTGRES is passed to the command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    # The setup script expects IMAGE_POSTGRES environment variable
    assert 'IMAGE_POSTGRES=' in command_str, \
        f"Command must pass IMAGE_POSTGRES variable to setup script, got: {command_str}"


def test_install_pagila_uses_correct_image_from_context():
    """install_pagila must use the correct image from context"""
    mock_runner = MockActionRunner()
    custom_image = 'mycorp.jfrog.io/team/postgres:17.5-alpine'
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.postgres_image': custom_image
    }

    install_pagila(ctx, mock_runner)

    # Assert the custom image is in the command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    assert custom_image in command_str, \
        f"Command must include the custom image {custom_image}, got: {command_str}"


# ============================================================================
# NON-INTERACTIVE SETUP TESTS - RED PHASE
# ============================================================================

def test_install_pagila_calls_setup_script_non_interactively():
    """install_pagila should call setup-pagila.sh with --yes flag for non-interactive mode"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git'
    }

    install_pagila(ctx, mock_runner)

    # The setup script supports --yes flag (line 89 in setup-pagila.sh)
    # When called from wizard, it must use --yes to avoid interactive prompts
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    # The command should include PAGILA_AUTO_YES=1 as a make variable
    # This will be passed to the setup script to enable non-interactive mode
    assert 'PAGILA_AUTO_YES=' in command_str, \
        f"Command must include PAGILA_AUTO_YES variable for non-interactive setup, got: {command_str}"


def test_install_pagila_passes_auto_yes_flag():
    """install_pagila should pass PAGILA_AUTO_YES=1 to avoid interactive prompts"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.postgres_image': 'postgres:17.5-alpine'
    }

    install_pagila(ctx, mock_runner)

    # Assert PAGILA_AUTO_YES=1 is in the command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    assert 'PAGILA_AUTO_YES=1' in command_str, \
        f"Command must pass PAGILA_AUTO_YES=1 to prevent stalling on prompts, got: {command_str}"


def test_install_pagila_non_interactive_prevents_stall():
    """install_pagila must avoid interactive prompts that would stall wizard execution"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git'
    }

    install_pagila(ctx, mock_runner)

    # The setup-pagila.sh script has 3 interactive prompts:
    # - Line 192: Clean up old resources (ask_yes_no)
    # - Line 241: Update pagila repository (ask_yes_no)
    # - Line 330: Restart pagila container (ask_yes_no)
    #
    # These prompts will stall indefinitely if called without --yes or PAGILA_AUTO_YES=1
    # The wizard must pass the flag to ensure non-blocking execution

    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    # Verify non-interactive mode is enabled
    has_auto_yes = 'PAGILA_AUTO_YES=' in command_str
    assert has_auto_yes, \
        f"Command must enable non-interactive mode to prevent wizard stall. Got: {command_str}"


# ============================================================================
# BRANCH SELECTION TESTS - RED PHASE
# ============================================================================

def test_save_config_stores_branch():
    """save_config should store the Pagila branch in config when specified"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.branch': 'feature/custom-schema',
        'services.pagila.enabled': True
    }

    save_config(ctx, mock_runner)

    # Assert branch is stored in config
    config = mock_runner.calls[0][1]
    assert 'services' in config
    assert 'pagila' in config['services']
    assert config['services']['pagila']['branch'] == 'feature/custom-schema'


def test_save_config_branch_optional():
    """save_config should work without branch (backward compatibility)"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.enabled': True
        # Note: no branch specified
    }

    save_config(ctx, mock_runner)

    # Should not fail, config should be saved successfully
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'


def test_install_pagila_passes_branch_to_setup():
    """install_pagila should pass PAGILA_BRANCH to setup script when branch specified"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.branch': 'develop'
    }

    install_pagila(ctx, mock_runner)

    # Assert PAGILA_BRANCH is in the command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    assert 'PAGILA_BRANCH=' in command_str, \
        f"Command must pass PAGILA_BRANCH variable when branch specified, got: {command_str}"


def test_install_pagila_uses_correct_branch_value():
    """install_pagila must pass the exact branch value from context"""
    mock_runner = MockActionRunner()
    custom_branch = 'feature/test-branch'
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.branch': custom_branch
    }

    install_pagila(ctx, mock_runner)

    # Assert the custom branch is in the command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    assert custom_branch in command_str, \
        f"Command must include the custom branch {custom_branch}, got: {command_str}"


def test_install_pagila_no_branch_when_empty():
    """install_pagila should not pass PAGILA_BRANCH when branch is empty or not specified"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git',
        'services.pagila.branch': ''  # Empty branch
    }

    install_pagila(ctx, mock_runner)

    # Assert PAGILA_BRANCH is not in the command (or is empty)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    command = run_shell_calls[0][1]
    command_str = ' '.join(command)

    # Should either not have PAGILA_BRANCH or have it empty
    # This ensures we use default branch when not specified
    if 'PAGILA_BRANCH=' in command_str:
        # If it's present, it should be empty or just "PAGILA_BRANCH="
        import re
        match = re.search(r'PAGILA_BRANCH=(\S*)', command_str)
        if match:
            branch_value = match.group(1)
            assert branch_value == '', \
                f"PAGILA_BRANCH should be empty when not specified, got: {branch_value}"


def test_install_pagila_backward_compatible_no_branch():
    """install_pagila should work without branch in context (backward compatibility)"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/Troubladore/pagila.git'
        # Note: no branch key at all
    }

    # Should not fail
    install_pagila(ctx, mock_runner)

    # Assert command was executed successfully
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1


# ============================================================================
# PAGILA TEST CONTAINER ACTIONS TESTS - RED PHASE
# ============================================================================

def test_save_pagila_test_config_exists():
    """save_pagila_test_config function must exist and be callable."""
    from wizard.services.pagila.actions import save_pagila_test_config

    # Should be callable with (ctx, runner) signature
    assert callable(save_pagila_test_config)


def test_save_pagila_test_config_saves_to_platform_config():
    """save_pagila_test_config should save pagila_test config to platform-config.yaml."""
    from wizard.services.pagila.actions import save_pagila_test_config

    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.test_containers.pagila_test.use_prebuilt': True,
        'services.pagila.test_containers.pagila_test.image': 'mycompany/pagila-test:latest'
    }

    save_pagila_test_config(ctx, mock_runner)

    # Should call save_config
    save_config_calls = [call for call in mock_runner.calls if call[0] == 'save_config']
    assert len(save_config_calls) == 1, "Should call save_config exactly once"

    call = save_config_calls[0]
    config = call[1]
    path = call[2]

    # Should save to platform-config.yaml
    assert path == 'platform-config.yaml', "Should save to platform-config.yaml"

    # Should have test_containers configuration
    assert 'services' in config
    assert 'pagila' in config['services']
    assert 'test_containers' in config['services']['pagila']
    assert 'pagila_test' in config['services']['pagila']['test_containers']

    pagila_config = config['services']['pagila']['test_containers']['pagila_test']
    assert pagila_config['prebuilt'] is True
    assert pagila_config['image'] == 'mycompany/pagila-test:latest'


def test_save_pagila_test_config_saves_image_vars_to_env():
    """save_pagila_test_config should save image variables to .env file."""
    from wizard.services.pagila.actions import save_pagila_test_config

    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.test_containers.pagila_test.use_prebuilt': True,
        'services.pagila.test_containers.pagila_test.image': 'mycompany/pagila-test:latest'
    }

    save_pagila_test_config(ctx, mock_runner)

    # Should write to platform-bootstrap/.env file
    write_calls = [call for call in mock_runner.calls if call[0] == 'write_file']
    env_write_calls = [call for call in write_calls if call[1] == 'platform-bootstrap/.env']
    assert len(env_write_calls) >= 1, "Should write to platform-bootstrap/.env file"

    # Check if any of the write calls contains the expected content
    found_correct_content = False
    for call in env_write_calls:
        env_content = call[2]
        if 'IMAGE_PAGILA_TEST=mycompany/pagila-test:latest' in env_content and \
           'PAGILA_TEST_PREBUILT=true' in env_content:
            found_correct_content = True
            break

    assert found_correct_content, "Should contain IMAGE_PAGILA_TEST and PAGILA_TEST_PREBUILT variables"


def test_save_pagila_test_config_uses_defaults_when_not_configured():
    """save_pagila_test_config should use defaults (alpine:latest, false) if not configured."""
    from wizard.services.pagila.actions import save_pagila_test_config

    mock_runner = MockActionRunner()
    ctx = {}  # Empty context - should use defaults

    save_pagila_test_config(ctx, mock_runner)

    # Should call save_config
    save_config_calls = [call for call in mock_runner.calls if call[0] == 'save_config']
    assert len(save_config_calls) == 1, "Should call save_config exactly once"

    call = save_config_calls[0]
    config = call[1]

    # Should use default values
    test_containers = config['services']['pagila']['test_containers']
    assert test_containers['pagila_test']['prebuilt'] is False
    assert test_containers['pagila_test']['image'] == 'alpine:latest'

    # Should write defaults to platform-bootstrap/.env
    write_calls = [call for call in mock_runner.calls if call[0] == 'write_file']
    env_write_calls = [call for call in write_calls if call[1] == 'platform-bootstrap/.env']
    assert len(env_write_calls) >= 1, "Should write to platform-bootstrap/.env file"

    # Check if any of the write calls contains the expected content
    found_correct_content = False
    for call in env_write_calls:
        env_content = call[2]
        if 'IMAGE_PAGILA_TEST=alpine:latest' in env_content and \
           'PAGILA_TEST_PREBUILT=false' in env_content:
            found_correct_content = True
            break

    assert found_correct_content, "Should contain default IMAGE_PAGILA_TEST and PAGILA_TEST_PREBUILT variables"


# ============================================================================
# VERIFY PAGILA CONNECTION TESTS - RED PHASE
# ============================================================================

def test_verify_pagila_connection_exists():
    """verify_pagila_connection function must exist and be callable."""
    from wizard.services.pagila.actions import verify_pagila_connection

    # Should be callable with (ctx, runner) signature
    assert callable(verify_pagila_connection)


def test_verify_pagila_connection_tests_database():
    """verify_pagila_connection should test connection to Pagila database."""
    from wizard.services.pagila.actions import verify_pagila_connection

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {
        'stdout': 'pagila',
        'stderr': '',
        'returncode': 0
    }
    ctx = {}

    verify_pagila_connection(ctx, mock_runner)

    # Should run commands to test connection
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) >= 1, "Should run at least one shell command to test connection"

    # Should check for pagila database
    commands_str = ' '.join([' '.join(call[1]) for call in run_shell_calls])
    assert 'pagila' in commands_str.lower(), "Should check for pagila database"


def test_verify_pagila_connection_checks_tables():
    """verify_pagila_connection should verify Pagila tables exist."""
    from wizard.services.pagila.actions import verify_pagila_connection

    mock_runner = MockActionRunner()
    # The mock response needs to satisfy multiple checks:
    # 1. Database existence check (looks for 'pagila')
    # 2. Table check (looks for actor, film, etc.)
    mock_runner.responses['run_shell'] = {
        'stdout': 'pagila\nactor\ncategory\nfilm\ncustomer',
        'stderr': '',
        'returncode': 0
    }
    ctx = {}

    verify_pagila_connection(ctx, mock_runner)

    # Should display success message
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    success_messages = [call[1] for call in display_calls if 'success' in str(call[1]).lower() or '✓' in str(call[1])]
    assert len(success_messages) > 0, "Should display success message when connection works"


def test_verify_pagila_connection_handles_failure():
    """verify_pagila_connection should handle connection failures gracefully."""
    from wizard.services.pagila.actions import verify_pagila_connection

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {
        'stdout': '',
        'stderr': 'FATAL: database "pagila" does not exist',
        'returncode': 1
    }
    ctx = {}

    verify_pagila_connection(ctx, mock_runner)

    # Should display error message
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    error_messages = [call[1] for call in display_calls if 'error' in str(call[1]).lower() or 'fail' in str(call[1]).lower() or '✗' in str(call[1])]
    assert len(error_messages) > 0, "Should display error message when connection fails"


def test_verify_pagila_connection_uses_test_container():
    """verify_pagila_connection should use pagila-test container for testing."""
    from wizard.services.pagila.actions import verify_pagila_connection

    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {
        'stdout': 'pagila',
        'stderr': '',
        'returncode': 0
    }
    ctx = {}

    verify_pagila_connection(ctx, mock_runner)

    # Should use docker run with pagila-test container
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    commands_str = ' '.join([' '.join(call[1]) for call in run_shell_calls])

    # Should either build the test container or use it
    assert ('pagila-test' in commands_str or 'build-pagila-test' in commands_str), \
        "Should use pagila-test container for connection testing"
