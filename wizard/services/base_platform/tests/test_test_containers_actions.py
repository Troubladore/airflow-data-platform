"""Tests for test container actions - RED phase.

This file contains failing tests for actions that don't exist yet:
1. invoke_test_container_spec - loads and executes the test-containers sub-spec
2. save_test_container_config - saves test container config to platform-config.yaml and .env
"""

import pytest
import yaml
from pathlib import Path
from wizard.engine.runner import MockActionRunner


def test_invoke_test_container_spec_exists():
    """invoke_test_container_spec function must exist and be callable."""
    # This will fail until the function is implemented
    from wizard.services.base_platform.actions import invoke_test_container_spec

    # Should be callable with (ctx, runner) signature
    assert callable(invoke_test_container_spec)


def test_invoke_test_container_spec_loads_sub_spec():
    """invoke_test_container_spec should load sub-spec from correct path."""
    from wizard.services.base_platform.actions import invoke_test_container_spec

    mock_runner = MockActionRunner()
    ctx = {}

    # This will fail until the function is implemented
    invoke_test_container_spec(ctx, mock_runner)

    # Should check for test-containers-spec.yaml file existence
    file_exists_calls = [call for call in mock_runner.calls if call[0] == 'file_exists']
    assert len(file_exists_calls) > 0, "Should check if test-containers-spec.yaml exists"

    # Should check the correct path
    found_correct_path = False
    for call in file_exists_calls:
        if 'test-containers-spec.yaml' in str(call[1]):
            found_correct_path = True
            break

    assert found_correct_path, "Should check for test-containers-spec.yaml in correct location"


def test_invoke_test_container_spec_executes_sub_spec_via_spec_runner():
    """invoke_test_container_spec should execute sub-spec via SpecRunner."""
    from wizard.services.base_platform.actions import invoke_test_container_spec

    mock_runner = MockActionRunner()
    ctx = {}

    # This will fail until the function is implemented
    invoke_test_container_spec(ctx, mock_runner)

    # Should show that SpecRunner or similar mechanism would be called
    # Since we can't easily mock SpecRunner directly, we check for indication of execution
    assert len(mock_runner.calls) > 0, "Should make some runner calls when executing sub-spec"


def test_invoke_test_container_spec_returns_false_if_sub_spec_not_found():
    """invoke_test_container_spec should return False if sub-spec not found."""
    from wizard.services.base_platform.actions import invoke_test_container_spec

    mock_runner = MockActionRunner()
    ctx = {}

    # Mock file_exists to return False
    mock_runner.responses['file_exists'] = {
        'wizard/services/base_platform/test-containers-spec.yaml': False
    }

    # This will fail until the function is implemented
    result = invoke_test_container_spec(ctx, mock_runner)

    assert result is False, "Should return False when sub-spec not found"


def test_invoke_test_container_spec_returns_true_on_successful_execution():
    """invoke_test_container_spec should return True on successful execution."""
    from wizard.services.base_platform.actions import invoke_test_container_spec

    mock_runner = MockActionRunner()
    ctx = {}

    # Mock file_exists to return True
    mock_runner.responses['file_exists'] = {
        'wizard/services/base_platform/test-containers-spec.yaml': True
    }

    # This will fail until the function is implemented
    result = invoke_test_container_spec(ctx, mock_runner)

    assert result is True, "Should return True when sub-spec executed successfully"


def test_save_test_container_config_exists():
    """save_test_container_config function must exist and be callable."""
    # This will fail until the function is implemented
    from wizard.services.base_platform.actions import save_test_container_config

    # Should be callable with (ctx, runner) signature
    assert callable(save_test_container_config)


def test_save_test_container_config_saves_postgres_test_config():
    """save_test_container_config should save postgres_test config to platform-config.yaml."""
    from wizard.services.base_platform.actions import save_test_container_config

    mock_runner = MockActionRunner()
    ctx = {
        'services.base_platform.test_containers.postgres_test.use_prebuilt': True,
        'services.base_platform.test_containers.postgres_test.image': 'mycompany/postgres-test:latest'
    }

    # This will fail until the function is implemented
    save_test_container_config(ctx, mock_runner)

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
    assert 'base_platform' in config['services']
    assert 'test_containers' in config['services']['base_platform']
    assert 'postgres_test' in config['services']['base_platform']['test_containers']

    postgres_config = config['services']['base_platform']['test_containers']['postgres_test']
    assert postgres_config['prebuilt'] is True
    assert postgres_config['image'] == 'mycompany/postgres-test:latest'


def test_save_test_container_config_saves_sqlcmd_test_config():
    """save_test_container_config should save sqlcmd_test config to platform-config.yaml."""
    from wizard.services.base_platform.actions import save_test_container_config

    mock_runner = MockActionRunner()
    ctx = {
        'services.base_platform.test_containers.sqlcmd_test.use_prebuilt': False,
        'services.base_platform.test_containers.sqlcmd_test.image': 'alpine:latest'
    }

    # This will fail until the function is implemented
    save_test_container_config(ctx, mock_runner)

    # Should call save_config
    save_config_calls = [call for call in mock_runner.calls if call[0] == 'save_config']
    assert len(save_config_calls) == 1, "Should call save_config exactly once"

    call = save_config_calls[0]
    config = call[1]

    # Should have sqlcmd_test configuration
    assert 'sqlcmd_test' in config['services']['base_platform']['test_containers']

    sqlcmd_config = config['services']['base_platform']['test_containers']['sqlcmd_test']
    assert sqlcmd_config['prebuilt'] is False
    assert sqlcmd_config['image'] == 'alpine:latest'


def test_save_test_container_config_saves_image_vars_to_env():
    """save_test_container_config should save image variables to .env file."""
    from wizard.services.base_platform.actions import save_test_container_config

    mock_runner = MockActionRunner()
    ctx = {
        'services.base_platform.test_containers.postgres_test.use_prebuilt': True,
        'services.base_platform.test_containers.postgres_test.image': 'mycompany/postgres-test:latest',
        'services.base_platform.test_containers.sqlcmd_test.use_prebuilt': False,
        'services.base_platform.test_containers.sqlcmd_test.image': 'alpine:latest'
    }

    # This will fail until the function is implemented
    save_test_container_config(ctx, mock_runner)

    # Should write to platform-bootstrap/.env file
    write_calls = [call for call in mock_runner.calls if call[0] == 'write_file']
    env_write_calls = [call for call in write_calls if call[1] == 'platform-bootstrap/.env']
    assert len(env_write_calls) == 1, "Should write to platform-bootstrap/.env file exactly once"

    call = env_write_calls[0]
    env_content = call[2]

    # Should contain all image and prebuilt variables
    assert 'IMAGE_POSTGRES_TEST=mycompany/postgres-test:latest' in env_content
    assert 'POSTGRES_TEST_PREBUILT=true' in env_content
    assert 'IMAGE_SQLCMD_TEST=alpine:latest' in env_content
    assert 'SQLCMD_TEST_PREBUILT=false' in env_content


def test_save_test_container_config_uses_defaults_when_not_configured():
    """save_test_container_config should use defaults (alpine:latest, false) if not configured."""
    from wizard.services.base_platform.actions import save_test_container_config

    mock_runner = MockActionRunner()
    ctx = {}  # Empty context - should use defaults

    # This will fail until the function is implemented
    save_test_container_config(ctx, mock_runner)

    # Should call save_config
    save_config_calls = [call for call in mock_runner.calls if call[0] == 'save_config']
    assert len(save_config_calls) == 1, "Should call save_config exactly once"

    call = save_config_calls[0]
    config = call[1]

    # Should use default values
    test_containers = config['services']['base_platform']['test_containers']
    assert test_containers['postgres_test']['prebuilt'] is False
    assert test_containers['postgres_test']['image'] == 'alpine:latest'
    assert test_containers['sqlcmd_test']['prebuilt'] is False
    assert test_containers['sqlcmd_test']['image'] == 'alpine:latest'

    # Should write defaults to platform-bootstrap/.env
    write_calls = [call for call in mock_runner.calls if call[0] == 'write_file']
    env_write_calls = [call for call in write_calls if call[1] == 'platform-bootstrap/.env']
    assert len(env_write_calls) == 1, "Should write to platform-bootstrap/.env file exactly once"

    call = env_write_calls[0]
    env_content = call[2]

    assert 'IMAGE_POSTGRES_TEST=alpine:latest' in env_content
    assert 'POSTGRES_TEST_PREBUILT=false' in env_content
    assert 'IMAGE_SQLCMD_TEST=alpine:latest' in env_content
    assert 'SQLCMD_TEST_PREBUILT=false' in env_content