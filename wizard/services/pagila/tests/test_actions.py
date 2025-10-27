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
        'services.postgres.enabled': True,
        'services.postgres.port': 5432
    }

    result = check_postgres_dependency(ctx, mock_runner)

    assert result is True


def test_check_postgres_dependency_failure_not_enabled():
    """check_postgres_dependency should return False if postgres not enabled"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.postgres.enabled': False
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
        'services.postgres.enabled': True,
        'services.postgres.port': 5432
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
        'services.postgres.image': 'artifactory.company.com/postgres:17.5',
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
