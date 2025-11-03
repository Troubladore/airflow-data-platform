"""Tests for Kerberos section header display actions."""

from wizard.engine.runner import MockActionRunner


def test_display_kerberos_header():
    """Should display main Kerberos section header."""
    mock_runner = MockActionRunner()
    ctx = {}

    # Import the function (will fail initially in RED phase)
    from wizard.services.kerberos.actions import display_kerberos_header

    display_kerberos_header(ctx, mock_runner)

    # Get display calls
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Check for expected header elements
    assert any("Kerberos Configuration" in msg for msg in display_messages), \
        f"Should display 'Kerberos Configuration'. Messages: {display_messages}"
    assert any("=" * 50 in msg for msg in display_messages), \
        f"Should display separator line. Messages: {display_messages}"


def test_display_sql_test_header():
    """Should display SQL Server test subsection header."""
    mock_runner = MockActionRunner()
    ctx = {}

    # Import the function (will fail initially in RED phase)
    from wizard.services.kerberos.actions import display_sql_test_header

    display_sql_test_header(ctx, mock_runner)

    # Get display calls
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Check for expected header elements
    assert any("SQL Server Connection Test" in msg for msg in display_messages), \
        f"Should display 'SQL Server Connection Test'. Messages: {display_messages}"
    assert any("-" * 50 in msg for msg in display_messages), \
        f"Should display dash separator line. Messages: {display_messages}"


def test_display_postgres_test_header():
    """Should display PostgreSQL test subsection header."""
    mock_runner = MockActionRunner()
    ctx = {}

    # Import the function (will fail initially in RED phase)
    from wizard.services.kerberos.actions import display_postgres_test_header

    display_postgres_test_header(ctx, mock_runner)

    # Get display calls
    display_calls = [call for call in mock_runner.calls if call[0] == 'display']
    display_messages = [call[1] for call in display_calls]

    # Check for expected header elements
    assert any("PostgreSQL Connection Test" in msg for msg in display_messages), \
        f"Should display 'PostgreSQL Connection Test'. Messages: {display_messages}"
    assert any("-" * 50 in msg for msg in display_messages), \
        f"Should display dash separator line. Messages: {display_messages}"