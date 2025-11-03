"""Tests for SQL Server connection testing with Kerberos."""

from unittest.mock import Mock
from wizard.engine.runner import MockActionRunner


def test_sql_server_connection():
    """Should test SQL Server with sqlcmd-test container."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.sql_server_fqdn': 'sql.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Import the function (will fail initially in RED phase)
    from wizard.services.kerberos.actions import test_sql_server_connection

    test_sql_server_connection(ctx, mock_runner)

    # Verify run_shell was called
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) > 0, "Should call run_shell to test SQL Server"

    # Verify docker run command with sqlcmd-test
    cmd = run_shell_calls[0][1]  # Get the command array
    assert 'docker' in cmd[0], "Should use docker command"
    assert 'run' in cmd, "Should use docker run"

    # Check for test container reference - either platform/sqlcmd-test or just sqlcmd-test
    cmd_str = ' '.join(cmd)
    assert 'sqlcmd-test' in cmd_str, f"Should use sqlcmd-test container. Command: {cmd_str}"

    # Check for MSSQL tools 18 with trust certificate flag
    assert '/opt/mssql-tools18/bin/sqlcmd' in cmd_str, "Should use MSSQL tools 18"
    assert '-C' in cmd, "Should include -C flag for SQL Server 2025 preview"
    assert '-E' in cmd, "Should use Windows authentication (-E)"

    # Check for Kerberos ticket mount
    assert f'{ctx["services.kerberos.ticket_dir"]}:/tmp/krb5cc_1000:ro' in cmd_str or \
           f'-v {ctx["services.kerberos.ticket_dir"]}:/tmp/krb5cc_1000:ro' in cmd_str, \
           "Should mount Kerberos ticket"

    # Check for krb5.conf mount
    assert '/etc/krb5.conf:/etc/krb5.conf:ro' in cmd_str, "Should mount krb5.conf"

    # Check for KRB5CCNAME environment variable
    assert '-e' in cmd and 'KRB5CCNAME=/tmp/krb5cc_1000' in cmd_str, \
           "Should set KRB5CCNAME environment variable"

    # Check for FQDN
    assert ctx['services.kerberos.sql_server_fqdn'] in cmd, \
           "Should connect to specified SQL Server FQDN"


def test_sql_server_connection_success():
    """Should display success message when connection succeeds."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.sql_server_fqdn': 'sql.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Mock successful SQL Server response
    def mock_run_shell(cmd, cwd=None):
        if 'sqlcmd' in ' '.join(cmd):
            return {
                'returncode': 0,
                'stdout': 'Microsoft SQL Server 2025 (RTM-CU1) (KB5002652) - 16.0.1000.6',
                'stderr': ''
            }
        return {'returncode': 0, 'stdout': '', 'stderr': ''}

    original_run_shell = mock_runner.run_shell
    mock_runner.run_shell = lambda cmd, cwd=None: (
        original_run_shell(cmd, cwd),
        mock_run_shell(cmd, cwd)
    )[1]

    from wizard.services.kerberos.actions import test_sql_server_connection
    test_sql_server_connection(ctx, mock_runner)

    # Check for success message
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    assert any('✅' in msg and 'SQL Server connection successful' in msg
               for msg in display_messages), \
        f"Should display success message. Messages: {display_messages}"


def test_sql_server_connection_failure():
    """Should call diagnostic function when connection fails."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.sql_server_fqdn': 'sql.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Mock failed SQL Server response
    def mock_run_shell(cmd, cwd=None):
        if 'sqlcmd' in ' '.join(cmd):
            return {
                'returncode': 1,
                'stdout': '',
                'stderr': 'Login failed for user'
            }
        return {'returncode': 0, 'stdout': '', 'stderr': ''}

    original_run_shell = mock_runner.run_shell
    mock_runner.run_shell = lambda cmd, cwd=None: (
        original_run_shell(cmd, cwd),
        mock_run_shell(cmd, cwd)
    )[1]

    # We expect the diagnostic function to be called
    # For now, just check that we don't crash and some error handling occurs
    from wizard.services.kerberos.actions import test_sql_server_connection

    # Should not raise an exception even on failure
    test_sql_server_connection(ctx, mock_runner)

    # Verify run_shell was called
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) > 0, "Should attempt SQL Server connection"