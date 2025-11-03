"""Tests for PostgreSQL connection testing with Kerberos."""

from wizard.engine.runner import MockActionRunner


def test_postgres_connection():
    """Should test PostgreSQL with postgres-test container."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.postgres_fqdn': 'pg.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Import the function (already implemented)
    from wizard.services.kerberos.actions import test_postgres_connection

    test_postgres_connection(ctx, mock_runner)

    # Verify run_shell was called
    run_shell_calls = [call for call in mock_runner.calls if call[0] == 'run_shell']
    assert len(run_shell_calls) > 0, "Should call run_shell to test PostgreSQL"

    # Verify docker run command with postgres-test
    cmd = run_shell_calls[0][1]  # Get the command array
    assert 'docker' in cmd[0], "Should use docker command"
    assert 'run' in cmd, "Should use docker run"

    # Check for test container reference
    cmd_str = ' '.join(cmd)
    assert 'postgres-test' in cmd_str, f"Should use postgres-test container. Command: {cmd_str}"

    # Check for psql command
    assert 'psql' in cmd_str, "Should use psql client"

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
    assert ctx['services.kerberos.postgres_fqdn'] in cmd, \
           "Should connect to specified PostgreSQL FQDN"


def test_postgres_connection_success():
    """Should display success message when connection succeeds."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.postgres_fqdn': 'pg.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Mock successful PostgreSQL response
    def mock_run_shell(cmd, cwd=None):
        if 'psql' in ' '.join(cmd):
            return {
                'returncode': 0,
                'stdout': 'PostgreSQL 15.4 on x86_64-pc-linux-gnu',
                'stderr': ''
            }
        return {'returncode': 0, 'stdout': '', 'stderr': ''}

    original_run_shell = mock_runner.run_shell
    mock_runner.run_shell = lambda cmd, cwd=None: (
        original_run_shell(cmd, cwd),
        mock_run_shell(cmd, cwd)
    )[1]

    from wizard.services.kerberos.actions import test_postgres_connection
    test_postgres_connection(ctx, mock_runner)

    # Check for success message
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    assert any('✅' in msg and 'PostgreSQL connection successful' in msg
               for msg in display_messages), \
        f"Should display success message. Messages: {display_messages}"


def test_postgres_connection_failure_gssapi():
    """Should provide GSSAPI-specific diagnostics when authentication fails."""
    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.postgres_fqdn': 'pg.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    # Mock GSSAPI authentication failure
    def mock_run_shell(cmd, cwd=None):
        if 'psql' in ' '.join(cmd):
            return {
                'returncode': 1,
                'stdout': '',
                'stderr': 'FATAL: GSSAPI authentication failed for user "postgres"'
            }
        return {'returncode': 0, 'stdout': '', 'stderr': ''}

    original_run_shell = mock_runner.run_shell
    mock_runner.run_shell = lambda cmd, cwd=None: (
        original_run_shell(cmd, cwd),
        mock_run_shell(cmd, cwd)
    )[1]

    from wizard.services.kerberos.actions import test_postgres_connection
    test_postgres_connection(ctx, mock_runner)

    # Check for diagnostic messages
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    assert any('❌ PostgreSQL Connection Failed' in msg for msg in display_messages), \
        "Should display failure message"
    assert any('GSSAPI authentication failed' in msg for msg in display_messages), \
        "Should display the actual error"
    assert any('pg_hba.conf' in msg for msg in display_messages), \
        "Should suggest checking pg_hba.conf for GSSAPI"