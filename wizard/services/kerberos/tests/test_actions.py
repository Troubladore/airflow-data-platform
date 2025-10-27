"""Tests for Kerberos actions - RED phase"""
import pytest
from wizard.engine.runner import MockActionRunner
from wizard.services.kerberos.actions import save_config, test_kerberos, start_service


def test_save_config_saves_domain_and_image():
    """save_config saves domain and image to platform-config.yaml"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM',
        'services.kerberos.image': 'ubuntu:22.04',
        'services.kerberos.use_prebuilt': False
    }

    save_config(ctx, mock_runner)

    # Verify save_config was called with correct data
    assert len(mock_runner.calls) == 1
    call_type, config, path = mock_runner.calls[0]
    assert call_type == 'save_config'
    assert config['services']['kerberos']['domain'] == 'COMPANY.COM'
    assert config['services']['kerberos']['image'] == 'ubuntu:22.04'
    assert config['services']['kerberos']['use_prebuilt'] is False
    assert path == 'platform-config.yaml'


def test_save_config_saves_prebuilt_image():
    """save_config saves prebuilt image configuration"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'INTERNAL.NET',
        'services.kerberos.image': 'myregistry.com/kerberos:1.0',
        'services.kerberos.use_prebuilt': True
    }

    save_config(ctx, mock_runner)

    # Verify prebuilt flag is saved
    call_type, config, path = mock_runner.calls[0]
    assert config['services']['kerberos']['use_prebuilt'] is True


def test_save_config_enables_kerberos_service():
    """save_config sets enabled flag to true"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'TEST.COM',
        'services.kerberos.image': 'ubuntu:22.04',
        'services.kerberos.use_prebuilt': False
    }

    save_config(ctx, mock_runner)

    call_type, config, path = mock_runner.calls[0]
    assert config['services']['kerberos']['enabled'] is True


def test_test_kerberos_uses_mock_runner():
    """test_kerberos calls runner but doesn't actually test Kerberos"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM'
    }

    # Mock successful Kerberos test
    mock_runner.responses['run_shell'] = {
        'stdout': 'Kerberos test successful',
        'stderr': '',
        'returncode': 0
    }

    test_kerberos(ctx, mock_runner)

    # CRITICAL: Verify runner was called but didn't actually test Kerberos
    assert len(mock_runner.calls) > 0
    assert any(call[0] == 'run_shell' for call in mock_runner.calls)
    # Verify it's a mock test command, not real Kerberos
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) == 1
    command = run_shell_calls[0][1]
    # Should call make test or similar
    assert 'make' in command or 'test' in str(command).lower()


def test_test_kerberos_handles_failure():
    """test_kerberos handles test failure gracefully"""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM'
    }

    # Mock failed Kerberos test
    mock_runner.responses['run_shell'] = {
        'stdout': '',
        'stderr': 'Connection refused',
        'returncode': 1
    }

    # Should not raise exception, just return failure
    result = test_kerberos(ctx, mock_runner)

    assert result is not None
    # Verify it was called
    assert len(mock_runner.calls) > 0


def test_start_service_calls_make_start():
    """start_service calls make start for Kerberos service"""
    mock_runner = MockActionRunner()
    ctx = {}

    mock_runner.responses['run_shell'] = {
        'stdout': 'Starting Kerberos service...',
        'stderr': '',
        'returncode': 0
    }

    start_service(ctx, mock_runner)

    # Verify make start was called
    assert len(mock_runner.calls) == 1
    call_type, command, cwd = mock_runner.calls[0]
    assert call_type == 'run_shell'
    assert 'make' in command
    assert 'start' in command


def test_start_service_with_working_directory():
    """start_service calls make in correct directory"""
    mock_runner = MockActionRunner()
    ctx = {}

    mock_runner.responses['run_shell'] = {
        'stdout': 'Service started',
        'stderr': '',
        'returncode': 0
    }

    start_service(ctx, mock_runner)

    # Verify working directory is set
    call_type, command, cwd = mock_runner.calls[0]
    assert cwd is not None or 'platform-infrastructure' in ' '.join(command)


# ============================================================================
# RED PHASE: Interface Compliance Tests (MUST FAIL)
# ============================================================================
# These tests verify actions follow the wizard interface:
# - Accept (ctx, runner) signature
# - Use runner for all I/O operations (no direct file/shell access)
# ============================================================================


def test_test_kerberos_signature_matches_interface():
    """test_kerberos must accept (ctx, runner) signature."""
    import inspect
    sig = inspect.signature(test_kerberos)
    params = list(sig.parameters.keys())
    assert params == ['ctx', 'runner'], f"Expected ['ctx', 'runner'], got {params}"


def test_save_config_uses_runner_interface():
    """save_config must use runner, not direct I/O."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.realm': 'COMPANY.COM',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    save_config(ctx, mock_runner)

    assert len(mock_runner.calls) == 1
    assert mock_runner.calls[0][0] == 'save_config'


# ============================================================================
# RED PHASE: Bug fix for blank container name and realm display
# ============================================================================


def test_start_service_displays_mock_container_info_in_non_domain_environment():
    """start_service must display container name and realm when creating mock container.

    Bug reproduction: User reported seeing blank values:
        Container: kerberos-sidecar-mock
        Mock realm:

    This test verifies that both container name and realm are properly displayed.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'TEST.LOCAL',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    # Mock non-domain environment (no $USERDNSDOMAIN)
    mock_runner.responses['run_shell'] = {
        'stdout': '',  # Empty stdout means not in domain
        'stderr': '',
        'returncode': 0
    }

    start_service(ctx, mock_runner)

    # Find all display calls
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Verify container name is displayed and NOT blank
    container_messages = [msg for msg in display_messages if 'Container:' in msg]
    assert len(container_messages) == 1, f"Expected 1 container message, got {len(container_messages)}"
    container_msg = container_messages[0]

    # The message should contain the actual container name, not be blank after "Container:"
    assert 'kerberos-sidecar-mock' in container_msg, \
        f"Container name missing in message: {container_msg}"

    # Verify realm is displayed and NOT blank
    realm_messages = [msg for msg in display_messages if 'Mock realm:' in msg]
    assert len(realm_messages) == 1, f"Expected 1 realm message, got {len(realm_messages)}"
    realm_msg = realm_messages[0]

    # The message should contain the actual realm, not be blank after "Mock realm:"
    assert 'TEST.LOCAL' in realm_msg, \
        f"Realm missing in message: {realm_msg}"

    # Verify the full message format
    assert 'Mock realm: TEST.LOCAL' in realm_msg, \
        f"Expected 'Mock realm: TEST.LOCAL' but got: {realm_msg}"


def test_start_service_displays_default_realm_when_domain_is_empty_string():
    """start_service must display default realm when domain is empty string in context.

    Bug reproduction: User reported seeing blank realm value:
        Mock realm:

    This happens when ctx contains services.kerberos.domain = '' (empty string).
    The .get() method returns the empty string instead of using the default.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': '',  # Empty string causes blank display
        'services.kerberos.image': 'ubuntu:22.04'
    }

    # Mock non-domain environment (no $USERDNSDOMAIN)
    mock_runner.responses['run_shell'] = {
        'stdout': '',  # Empty stdout means not in domain
        'stderr': '',
        'returncode': 0
    }

    start_service(ctx, mock_runner)

    # Find all display calls
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Verify realm is displayed with default value (not blank)
    realm_messages = [msg for msg in display_messages if 'Mock realm:' in msg]
    assert len(realm_messages) == 1, f"Expected 1 realm message, got {len(realm_messages)}"
    realm_msg = realm_messages[0]

    # Should display the default MOCK.LOCAL, not blank
    assert 'MOCK.LOCAL' in realm_msg, \
        f"Expected default realm 'MOCK.LOCAL' but got blank: '{realm_msg}'"
