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

    # Mock successful Kerberos test - all commands succeed
    mock_runner.responses['run_shell'] = {
        'stdout': 'Kerberos test successful',
        'stderr': '',
        'returncode': 0
    }

    test_kerberos(ctx, mock_runner)

    # CRITICAL: Verify runner was called but didn't actually test Kerberos
    # The function makes multiple shell calls:
    # 1. which klist (check for tool)
    # 2. klist -s (check for tickets)
    # 3. klist (get ticket details)
    # 4. nslookup (check domain)
    # 5. test -f (check krb5.conf)
    # So we expect multiple calls to run_shell
    assert len(mock_runner.calls) > 0
    assert any(call[0] == 'run_shell' for call in mock_runner.calls)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) >= 1, "Should make at least one shell call"


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

    # Verify make start was called (check run_shell calls only)
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    # Should have: check domain, maybe powershell, then make start
    assert any('make' in ' '.join(str(x) for x in call[1]) for call in run_shell_calls), \
        f"Expected make command in run_shell calls: {run_shell_calls}"
    assert any('start' in ' '.join(str(x) for x in call[1]) for call in run_shell_calls), \
        f"Expected start command in run_shell calls: {run_shell_calls}"


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

    # Verify working directory is set for make command
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    # Find the make command
    make_calls = [call for call in run_shell_calls if 'make' in ' '.join(str(x) for x in call[1])]
    assert len(make_calls) > 0, f"Expected at least one make command: {run_shell_calls}"

    # Check that make command has cwd or includes platform path
    call_type, command, cwd = make_calls[0]
    assert cwd is not None or 'platform-bootstrap' in ' '.join(str(x) for x in command), \
        f"Expected cwd or platform path in make command: cwd={cwd}, command={command}"


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


# ============================================================================
# RED PHASE: WSL2 Domain Detection Tests (MUST FAIL FIRST)
# ============================================================================


def test_start_service_uses_userdnsdomain_when_available():
    """start_service should use USERDNSDOMAIN environment variable when set.

    This is the existing behavior that should continue to work.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.image': 'ubuntu:22.04'
    }

    # Mock USERDNSDOMAIN being set (first check returns domain)
    mock_runner.responses['run_shell'] = {
        'stdout': 'COMPANY.COM',  # USERDNSDOMAIN is set
        'stderr': '',
        'returncode': 0
    }

    start_service(ctx, mock_runner)

    # Should detect domain and start real Kerberos sidecar
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show domain detected message
    assert any('Detected domain environment' in msg for msg in display_messages), \
        f"Should detect domain when USERDNSDOMAIN is set. Messages: {display_messages}"


def test_start_service_uses_powershell_fallback_when_userdnsdomain_empty():
    """start_service should try PowerShell when USERDNSDOMAIN is empty (WSL2 case).

    Bug fix: WSL2 on domain-joined machines don't have USERDNSDOMAIN set,
    but can get domain via PowerShell.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.image': 'ubuntu:22.04'
    }

    # First call checks USERDNSDOMAIN (empty in WSL2)
    # Second call checks if PowerShell exists
    # Third call runs PowerShell
    call_count = [0]
    def mock_run_shell_handler(command, cwd=None):
        call_count[0] += 1
        if call_count[0] == 1:
            # First call: check USERDNSDOMAIN - empty in WSL2
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 2:
            # Second call: check if powershell.exe exists (command -v)
            if 'command -v powershell.exe' in ' '.join(command):
                return {'stdout': '/mnt/c/.../powershell.exe', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 3:
            # Third call: PowerShell fallback returns domain
            if 'powershell.exe' in command:
                return {'stdout': 'COMPANY.COM\n', 'stderr': '', 'returncode': 0}
        # Subsequent calls for make commands
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    # Use custom handler
    original_run_shell = mock_runner.run_shell
    def custom_run_shell(command, cwd=None):
        result = mock_run_shell_handler(command, cwd)
        original_run_shell(command, cwd)  # Still record the call
        return result

    mock_runner.run_shell = custom_run_shell

    start_service(ctx, mock_runner)

    # Should detect domain via PowerShell and start real Kerberos sidecar
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show domain detected message
    assert any('Detected domain environment' in msg for msg in display_messages), \
        f"Should detect domain via PowerShell fallback. Messages: {display_messages}"

    # Should NOT show mock container messages
    assert not any('Mock Kerberos container' in msg for msg in display_messages), \
        f"Should not create mock container when domain detected via PowerShell"


def test_start_service_handles_powershell_not_available():
    """start_service should handle cases where PowerShell is not available (native Linux).

    Native Linux systems won't have powershell.exe, so the fallback should
    gracefully handle this and fall back to mock mode.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'MOCK.LOCAL',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    call_count = [0]
    def mock_run_shell_handler(command, cwd=None):
        call_count[0] += 1
        if call_count[0] == 1:
            # First call: check USERDNSDOMAIN - empty
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 2:
            # Second call: check if powershell.exe exists (command -v powershell.exe)
            if 'command -v powershell.exe' in ' '.join(command):
                return {'stdout': '', 'stderr': '', 'returncode': 1}  # Not found
        # Subsequent calls for docker commands
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    original_run_shell = mock_runner.run_shell
    def custom_run_shell(command, cwd=None):
        result = mock_run_shell_handler(command, cwd)
        original_run_shell(command, cwd)
        return result

    mock_runner.run_shell = custom_run_shell

    start_service(ctx, mock_runner)

    # Should fall back to mock mode
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show non-domain message and create mock container
    assert any('Detected non-domain environment' in msg for msg in display_messages), \
        f"Should detect non-domain when PowerShell not available. Messages: {display_messages}"
    assert any('Mock Kerberos container' in msg for msg in display_messages), \
        f"Should create mock container when not in domain. Messages: {display_messages}"


def test_start_service_should_verify_domain_matches_configured_domain():
    """Should verify the detected domain matches what user configured.

    Bug: User configures domain as "MYCORP.COM" but PowerShell might return
    a different domain or format. We should at least warn if they don't match.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'MYCORP.COM',
        'services.kerberos.image': 'mykerberos-image:latest',
        'services.kerberos.use_prebuilt': True
    }

    call_count = [0]
    def mock_run_shell_handler(command, cwd=None):
        call_count[0] += 1
        if call_count[0] == 1:
            # First call: check USERDNSDOMAIN - empty in WSL2
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 2:
            # Second call: check if powershell.exe exists
            if 'command -v powershell.exe' in ' '.join(command):
                return {'stdout': '/mnt/c/.../powershell.exe', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 3:
            # PowerShell returns the actual domain
            if 'powershell.exe' in command:
                return {'stdout': 'MYCORP.COM\n', 'stderr': '', 'returncode': 0}
        # Subsequent calls for make commands
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    original_run_shell = mock_runner.run_shell
    def custom_run_shell(command, cwd=None):
        result = mock_run_shell_handler(command, cwd)
        original_run_shell(command, cwd)
        return result

    mock_runner.run_shell = custom_run_shell

    start_service(ctx, mock_runner)

    # Should detect domain environment
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should recognize we're in a domain
    assert any('Detected domain environment' in msg for msg in display_messages), \
        f"Should detect domain when PowerShell returns MYCORP.COM. Messages: {display_messages}"

    # Should NOT create mock container
    assert not any('Mock Kerberos container' in msg for msg in display_messages), \
        f"Should NOT create mock container when domain detected. Messages: {display_messages}"


def test_start_service_detects_domain_when_powershell_returns_empty_with_success_code():
    """PowerShell may return success (0) with empty stdout when not domain-joined.

    Bug: Current code only checks returncode == 0, not whether stdout contains
    a valid domain. This causes false positives where we think we're in a domain
    when we're not.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'MYCORP.COM',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    call_count = [0]
    def mock_run_shell_handler(command, cwd=None):
        call_count[0] += 1
        if call_count[0] == 1:
            # First call: check USERDNSDOMAIN - empty
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 2:
            # Second call: check if powershell.exe exists
            if 'command -v powershell.exe' in ' '.join(command):
                return {'stdout': '/mnt/c/.../powershell.exe', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 3:
            # Third call: PowerShell returns SUCCESS but EMPTY stdout (not on domain)
            # This is the bug - returncode 0 but no domain in stdout
            if 'powershell.exe' in command:
                return {'stdout': '\n', 'stderr': '', 'returncode': 0}  # Empty/whitespace
        # Subsequent calls for docker commands
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    original_run_shell = mock_runner.run_shell
    def custom_run_shell(command, cwd=None):
        result = mock_run_shell_handler(command, cwd)
        original_run_shell(command, cwd)
        return result

    mock_runner.run_shell = custom_run_shell

    start_service(ctx, mock_runner)

    # Should NOT detect domain (PowerShell returned empty)
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show NON-domain message since PowerShell returned empty
    assert any('Detected non-domain environment' in msg for msg in display_messages), \
        f"Should detect non-domain when PowerShell returns empty stdout. Messages: {display_messages}"
    assert any('Mock Kerberos container' in msg for msg in display_messages), \
        f"Should create mock container when PowerShell returns empty. Messages: {display_messages}"

    # Should NOT think we're in a domain
    assert not any('Detected domain environment' in msg for msg in display_messages), \
        f"Should NOT detect domain when PowerShell returns empty stdout"


def test_start_service_handles_powershell_domain_error():
    """start_service should handle PowerShell errors gracefully (not domain-joined).

    WSL2 on non-domain Windows machines will have powershell.exe but will
    return an error when querying domain. Should fall back to mock mode.
    """
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'MOCK.LOCAL',
        'services.kerberos.image': 'ubuntu:22.04'
    }

    call_count = [0]
    def mock_run_shell_handler(command, cwd=None):
        call_count[0] += 1
        if call_count[0] == 1:
            # First call: check USERDNSDOMAIN - empty
            return {'stdout': '', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 2:
            # Second call: check if powershell.exe exists (command -v)
            if 'command -v powershell.exe' in ' '.join(command):
                return {'stdout': '/mnt/c/.../powershell.exe', 'stderr': '', 'returncode': 0}
        elif call_count[0] == 3:
            # Third call: PowerShell returns error (not domain-joined)
            if 'powershell.exe' in command:
                return {'stdout': '', 'stderr': 'Exception calling GetComputerDomain', 'returncode': 1}
        # Subsequent calls for docker commands
        return {'stdout': '', 'stderr': '', 'returncode': 0}

    original_run_shell = mock_runner.run_shell
    def custom_run_shell(command, cwd=None):
        result = mock_run_shell_handler(command, cwd)
        original_run_shell(command, cwd)
        return result

    mock_runner.run_shell = custom_run_shell

    start_service(ctx, mock_runner)

    # Should fall back to mock mode
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show non-domain message and create mock container
    assert any('Detected non-domain environment' in msg for msg in display_messages), \
        f"Should detect non-domain when PowerShell returns error. Messages: {display_messages}"
    assert any('Mock Kerberos container' in msg for msg in display_messages), \
        f"Should create mock container when not in domain. Messages: {display_messages}"
