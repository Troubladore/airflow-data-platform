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
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Assert command includes pagila setup
    command = mock_runner.calls[0][1]
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
    command = mock_runner.calls[0][1]
    command_str = ' '.join(command)
    assert repo_url in command_str or 'PAGILA_REPO' in command_str


def test_install_pagila_uses_make_target():
    """install_pagila should use make target for consistency"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.pagila.repo_url': 'https://github.com/devrimgunduz/pagila.git'
    }

    install_pagila(ctx, mock_runner)

    # Assert make command is used
    command = mock_runner.calls[0][1]
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
