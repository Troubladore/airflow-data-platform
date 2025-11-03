"""Tests for Kerberos diagnostic functions."""

import os
from unittest.mock import Mock, patch
from wizard.engine.runner import MockActionRunner


def test_parse_krb5_config():
    """Should parse krb5.conf file and extract configuration."""
    from wizard.services.kerberos.diagnostics import parse_krb5_config

    # Mock krb5.conf content
    sample_krb5 = """[libdefaults]
    default_realm = COMPANY.COM
    ticket_lifetime = 24h
    forwardable = true

[realms]
    COMPANY.COM = {
        kdc = dc1.company.com
        kdc = dc2.company.com
        admin_server = dc1.company.com
    }

[domain_realm]
    .company.com = COMPANY.COM
    company.com = COMPANY.COM
"""

    with patch('builtins.open', create=True) as mock_open:
        mock_open.return_value.__enter__.return_value.read.return_value = sample_krb5
        with patch('os.path.exists', return_value=True):
            config = parse_krb5_config()

    assert 'default_realm' in config
    assert config['default_realm'] == 'COMPANY.COM'
    assert 'realms' in config
    assert 'COMPANY.COM' in config['realms']
    assert 'kdc' in config['realms']['COMPANY.COM']
    assert 'domain_realm' in config


def test_parse_krb5_config_missing_file():
    """Should return empty dict when krb5.conf doesn't exist."""
    from wizard.services.kerberos.diagnostics import parse_krb5_config

    with patch('os.path.exists', return_value=False):
        config = parse_krb5_config()

    assert config == {}


def test_parse_ticket_status():
    """Should parse klist output and return ticket status."""
    from wizard.services.kerberos.diagnostics import parse_ticket_status

    # Mock klist output
    klist_result = {
        'returncode': 0,
        'stdout': """Ticket cache: FILE:/tmp/krb5cc_1000
Default principal: user@COMPANY.COM

Valid starting     Expires            Service principal
01/01/24 09:00:00  01/02/24 09:00:00  krbtgt/COMPANY.COM@COMPANY.COM
""",
        'stderr': ''
    }

    status = parse_ticket_status(klist_result)

    assert 'valid' in status.lower() or 'active' in status.lower()
    assert 'user@COMPANY.COM' in status


def test_parse_ticket_status_no_tickets():
    """Should indicate when no tickets are present."""
    from wizard.services.kerberos.diagnostics import parse_ticket_status

    klist_result = {
        'returncode': 1,
        'stdout': '',
        'stderr': 'klist: No credentials cache found'
    }

    status = parse_ticket_status(klist_result)

    assert 'no' in status.lower() or 'not found' in status.lower()


def test_diagnose_sql_failure_with_krb5_parsing():
    """Should use krb5.conf data in SQL diagnostics."""
    mock_runner = MockActionRunner()
    ctx = {'services.kerberos.sql_server_fqdn': 'sql.company.com'}
    result = {'returncode': 1, 'stderr': 'Cannot generate SSPI context'}

    # Mock krb5.conf to return test data
    mock_krb5_config = {
        'default_realm': 'COMPANY.COM',
        'realms': {
            'COMPANY.COM': {
                'kdc': ['dc1.company.com', 'dc2.company.com']
            }
        }
    }

    # Mock klist to return no tickets
    def mock_run_shell(cmd, cwd=None):
        if 'klist' in cmd:
            return {'returncode': 1, 'stdout': '', 'stderr': 'No credentials cache found'}
        return {'returncode': 0, 'stdout': '', 'stderr': ''}

    original_run_shell = mock_runner.run_shell
    mock_runner.run_shell = lambda cmd, cwd=None: (
        original_run_shell(cmd, cwd),
        mock_run_shell(cmd, cwd)
    )[1]

    with patch('wizard.services.kerberos.diagnostics.parse_krb5_config', return_value=mock_krb5_config):
        from wizard.services.kerberos.actions import diagnose_sql_failure
        diagnose_sql_failure(ctx, mock_runner, result)

    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Should show the primary error
    assert any('Cannot generate SSPI context' in msg for msg in display_messages)

    # Should check and report on Kerberos status
    assert any('Kerberos' in msg for msg in display_messages)


def test_extended_diagnostics():
    """Should provide extended diagnostics with krb5.conf details."""
    from wizard.services.kerberos.diagnostics import run_extended_diagnostics

    mock_runner = MockActionRunner()
    ctx = {
        'services.kerberos.domain': 'COMPANY.COM',
        'services.kerberos.sql_server_fqdn': 'sql.company.com'
    }

    mock_krb5_config = {
        'default_realm': 'WRONGREALM.COM',  # Mismatch!
        'realms': {
            'WRONGREALM.COM': {
                'kdc': ['dc.wrongrealm.com']
            }
        }
    }

    with patch('wizard.services.kerberos.diagnostics.parse_krb5_config', return_value=mock_krb5_config):
        diagnostics = run_extended_diagnostics(ctx, mock_runner)

    # Should detect realm mismatch
    assert 'realm_mismatch' in diagnostics or 'configuration_issues' in diagnostics

    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = ' '.join([call[1] for call in display_calls])

    # Should report the mismatch
    assert 'WRONGREALM.COM' in display_messages or 'realm' in display_messages.lower()