"""Tests for OpenMetadata actions - RED phase"""
import pytest
import inspect
from wizard.services.openmetadata.actions import save_config, start_service, check_dependencies
from wizard.engine.runner import MockActionRunner


def test_save_config_with_prebuilt_images():
    """Saves config with prebuilt server and opensearch images"""
    # Set up context with all required fields
    ctx = {
        'services.openmetadata.server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
        'services.openmetadata.opensearch_image': 'opensearchproject/opensearch:2.9.0',
        'services.openmetadata.port': 8585,
        'services.openmetadata.use_prebuilt': True
    }

    # Use MockActionRunner to capture save_config call
    mock_runner = MockActionRunner()
    save_config(ctx, mock_runner)

    # Verify runner.save_config was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'

    # Extract the config that would be saved (calls[0][1] is the config dict)
    saved_config = mock_runner.calls[0][1]

    assert saved_config["services"]["openmetadata"]["server_image"] == "docker.getcollate.io/openmetadata/server:1.5.0"
    assert saved_config["services"]["openmetadata"]["opensearch_image"] == "opensearchproject/opensearch:2.9.0"
    assert saved_config["services"]["openmetadata"]["port"] == 8585
    assert saved_config["services"]["openmetadata"]["use_prebuilt"] is True


def test_save_config_without_prebuilt_images():
    """Saves config with build-from-source (no prebuilt images)"""
    # Set up context without images (None means not provided)
    ctx = {
        'services.openmetadata.port': 8585,
        'services.openmetadata.use_prebuilt': False
    }

    # Use MockActionRunner to capture save_config call
    mock_runner = MockActionRunner()
    save_config(ctx, mock_runner)

    # Verify runner.save_config was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'

    # Extract the config that would be saved (calls[0][1] is the config dict)
    saved_config = mock_runner.calls[0][1]

    assert saved_config["services"]["openmetadata"]["use_prebuilt"] is False
    assert "server_image" not in saved_config["services"]["openmetadata"]
    assert "opensearch_image" not in saved_config["services"]["openmetadata"]


def test_save_config_preserves_existing_config():
    """Saves config while preserving existing non-openmetadata settings"""
    # Note: Config merging is handled by the runner, not the action
    # This test verifies that the action provides the correct structure
    ctx = {
        'services.openmetadata.server_image': 'docker.getcollate.io/openmetadata/server:1.5.0',
        'services.openmetadata.opensearch_image': 'opensearchproject/opensearch:2.9.0',
        'services.openmetadata.port': 8585,
        'services.openmetadata.use_prebuilt': True
    }

    mock_runner = MockActionRunner()
    save_config(ctx, mock_runner)

    # Verify the config structure allows merging (calls[0][1] is the config dict)
    saved_config = mock_runner.calls[0][1]
    assert "services" in saved_config
    assert "openmetadata" in saved_config["services"]
    # Runner will merge this with existing config


def test_start_service_calls_make_start():
    """Starts OpenMetadata service by calling make start"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'Service started'}
    ctx = {}

    start_service(ctx, mock_runner)

    # Verify runner.run_shell was called
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Verify command structure (calls[0][1] is the command list)
    command = mock_runner.calls[0][1]
    assert 'make' in command
    assert '-C' in command
    assert 'openmetadata' in command
    assert 'start' in command


def test_start_service_handles_failure():
    """Handles failure when make start fails"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 1, 'stderr': 'Error starting service'}
    ctx = {}

    # Note: start_service doesn't return a value, it just calls runner
    # The runner handles the failure
    start_service(ctx, mock_runner)

    # Verify runner was called
    assert len(mock_runner.calls) == 1


def test_check_dependencies_postgres_running():
    """Verifies postgres is running before starting OpenMetadata"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'postgres-container'}
    ctx = {}

    result = check_dependencies(ctx, mock_runner)

    assert result is True
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'run_shell'

    # Verify command structure (calls[0][1] is the command list)
    command = mock_runner.calls[0][1]
    assert 'docker' in command
    assert 'ps' in command


def test_check_dependencies_postgres_not_running():
    """Fails when postgres is not running"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': ''}
    ctx = {}

    result = check_dependencies(ctx, mock_runner)

    assert result is False


def test_check_dependencies_docker_error():
    """Handles docker command errors gracefully"""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 1, 'stderr': 'Cannot connect to Docker daemon'}
    ctx = {}

    result = check_dependencies(ctx, mock_runner)

    assert result is False


# === INTERFACE COMPLIANCE TESTS (RED PHASE) ===

def test_save_config_signature_matches_interface():
    """Action must accept (ctx, runner) signature."""
    sig = inspect.signature(save_config)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_save_config_uses_runner_not_direct_io():
    """Action must use runner.save_config, not direct file I/O."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.openmetadata.server_image': 'test:1.0',
        'services.openmetadata.opensearch_image': 'search:1.0'
    }

    save_config(ctx, mock_runner)

    # Verify runner.save_config was called (not direct file I/O)
    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'


def test_start_service_uses_runner_not_subprocess():
    """Action must use runner.run_shell, not subprocess.run."""
    mock_runner = MockActionRunner()
    ctx = {}

    start_service(ctx, mock_runner)

    # Verify runner.run_shell was called
    assert any(call[0] == 'run_shell' for call in mock_runner.calls)


def test_check_dependencies_uses_runner():
    """Action must use runner, not direct subprocess."""
    mock_runner = MockActionRunner()
    mock_runner.responses['run_shell'] = {'returncode': 0, 'stdout': 'postgres'}
    ctx = {}

    result = check_dependencies(ctx, mock_runner)

    # Verify used runner
    assert any(call[0] == 'run_shell' for call in mock_runner.calls)
