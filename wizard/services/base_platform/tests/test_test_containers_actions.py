"""Tests for test container actions.

Tests for save_test_container_config which saves test container config
to platform-config.yaml and .env.

Note: invoke_test_container_spec was removed as test container steps
are now inline in the main spec.yaml instead of a separate sub-spec.
"""

import pytest
import yaml
from pathlib import Path
from wizard.engine.runner import MockActionRunner


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