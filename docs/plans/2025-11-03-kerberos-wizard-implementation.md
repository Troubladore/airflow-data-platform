# Kerberos Wizard Consistency Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update Kerberos wizard to match base_platform/Pagila patterns with connection testing

**Architecture:** Add section headers, refactor progressive tests into SQL Server and PostgreSQL connection tests with detailed diagnostics

**Tech Stack:** Python, Docker, MSSQL Tools 18 (supports SQL Server 2025 preview)

---

## Task 1: Add Section Headers

**Files:**
- Modify: `wizard/services/kerberos/actions.py`
- Modify: `wizard/services/kerberos/spec.yaml`
- Test: `wizard/services/kerberos/tests/test_actions.py`

**Step 1: Write test for headers**
```python
# In test_actions.py
def test_display_kerberos_header():
    """Should display main Kerberos section header."""
    runner = Mock()
    ctx = {}

    actions.display_kerberos_header(ctx, runner)

    calls = [str(call) for call in runner.display.call_args_list]
    assert any("Kerberos Configuration" in call for call in calls)
    assert any("=" * 50 in call for call in calls)
```

**Step 2: Implement header functions**
```python
# In actions.py
def display_kerberos_header(ctx: Dict[str, Any], runner) -> None:
    """Display 'Kerberos Configuration' section header."""
    runner.display("")
    runner.display("Kerberos Configuration")
    runner.display("=" * 50)

def display_sql_test_header(ctx: Dict[str, Any], runner) -> None:
    """Display 'SQL Server Connection Test' subsection header."""
    runner.display("")
    runner.display("SQL Server Connection Test")
    runner.display("-" * 50)

def display_postgres_test_header(ctx: Dict[str, Any], runner) -> None:
    """Display 'PostgreSQL Connection Test' subsection header."""
    runner.display("")
    runner.display("PostgreSQL Connection Test")
    runner.display("-" * 50)
```

**Step 3: Update spec.yaml**
Add header steps before domain_input and test sections

---

## Task 2: SQL Server Connection Test

**Files:**
- Modify: `wizard/services/kerberos/actions.py`
- Test: `wizard/services/kerberos/tests/test_sql_connection.py`

**Step 1: Test for SQL connection**
```python
def test_sql_server_connection():
    """Should test SQL Server with sqlcmd-test container."""
    runner = Mock()
    ctx = {
        'services.kerberos.sql_server_fqdn': 'sql.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    result = actions.test_sql_server_connection(ctx, runner)

    assert runner.run_shell.called
    # Verify docker run command with sqlcmd-test
```

**Step 2: Implement connection test**
```python
def test_sql_server_connection(ctx: Dict[str, Any], runner) -> None:
    """Test SQL Server connection using sqlcmd-test container."""
    fqdn = ctx.get('services.kerberos.sql_server_fqdn')
    ticket_dir = ctx.get('services.kerberos.ticket_dir', '/tmp/krb5cc_1000')

    # Run sqlcmd-test container with Kerberos ticket mount
    cmd = [
        'docker', 'run', '--rm',
        '--network', 'platform_network',
        '-v', f'{ticket_dir}:/tmp/krb5cc_1000:ro',
        '-v', '/etc/krb5.conf:/etc/krb5.conf:ro',
        '-e', 'KRB5CCNAME=/tmp/krb5cc_1000',
        'sqlcmd-test',
        '/opt/mssql-tools18/bin/sqlcmd',
        '-S', fqdn,
        '-C',  # Trust server certificate (for SQL 2025 preview)
        '-E',  # Windows authentication
        '-Q', 'SELECT @@VERSION'
    ]

    result = runner.run_shell(cmd)

    if result['returncode'] == 0:
        runner.display(f"✅ SQL Server connection successful to {fqdn}")
    else:
        diagnose_sql_failure(ctx, runner, result)
```

---

## Task 3: PostgreSQL Connection Test

**Files:**
- Modify: `wizard/services/kerberos/actions.py`
- Test: `wizard/services/kerberos/tests/test_postgres_connection.py`

**Step 1: Test for PostgreSQL connection**
```python
def test_postgres_connection():
    """Should test PostgreSQL with postgres-test container."""
    runner = Mock()
    ctx = {
        'services.kerberos.postgres_fqdn': 'pg.company.com',
        'services.kerberos.ticket_dir': '/tmp/krb5cc_1000'
    }

    result = actions.test_postgres_connection(ctx, runner)

    assert runner.run_shell.called
    # Verify docker run command with postgres-test
```

**Step 2: Implement connection test**
```python
def test_postgres_connection(ctx: Dict[str, Any], runner) -> None:
    """Test PostgreSQL connection using postgres-test container."""
    fqdn = ctx.get('services.kerberos.postgres_fqdn')
    ticket_dir = ctx.get('services.kerberos.ticket_dir', '/tmp/krb5cc_1000')

    cmd = [
        'docker', 'run', '--rm',
        '--network', 'platform_network',
        '-v', f'{ticket_dir}:/tmp/krb5cc_1000:ro',
        '-v', '/etc/krb5.conf:/etc/krb5.conf:ro',
        '-e', 'KRB5CCNAME=/tmp/krb5cc_1000',
        'postgres-test',
        'psql',
        '-h', fqdn,
        '-U', 'postgres',
        '-c', 'SELECT version()'
    ]

    result = runner.run_shell(cmd)

    if result['returncode'] == 0:
        runner.display(f"✅ PostgreSQL connection successful to {fqdn}")
    else:
        diagnose_postgres_failure(ctx, runner, result)
```

---

## Task 4: Diagnostic Functions

**Files:**
- Create: `wizard/services/kerberos/diagnostics.py`
- Test: `wizard/services/kerberos/tests/test_diagnostics.py`

**Step 1: Parse krb5.conf**
```python
def parse_krb5_config() -> dict:
    """Parse krb5.conf for diagnostic information."""
    config = {}
    krb5_path = '/etc/krb5.conf'

    if os.path.exists(krb5_path):
        # Parse sections: [libdefaults], [realms], [domain_realm]
        # Return structured dict
    return config

def diagnose_sql_failure(ctx, runner, result):
    """Diagnose SQL Server connection failure."""
    runner.display("❌ SQL Server Connection Failed")
    runner.display("━" * 50)

    # Check Kerberos tickets
    klist_result = runner.run_shell(['klist'])

    # Parse krb5.conf
    krb5_config = parse_krb5_config()

    # Provide structured diagnostics
    runner.display(f"Primary Error: {result.get('stderr', 'Unknown')}")
    runner.display(f"Kerberos Status: {parse_ticket_status(klist_result)}")
    # ... more diagnostics
```

---

## Task 5: Update spec.yaml Flow

**Files:**
- Modify: `wizard/services/kerberos/spec.yaml`

Replace progressive test section with:
```yaml
  - id: sql_server_test_prompt
    type: boolean
    state_key: services.kerberos.test_sql_server
    prompt: "Do you have a SQL Server instance to test Kerberos authentication against?"
    default_value: false
    next:
      when_value:
        true: sql_server_fqdn_input
        false: postgres_test_prompt

  - id: sql_server_fqdn_input
    type: string
    state_key: services.kerberos.sql_server_fqdn
    prompt: "Enter SQL Server FQDN (e.g., sqlserver.company.com):"
    next: display_sql_test_header

  - id: display_sql_test_header
    type: action
    action: kerberos.display_sql_test_header
    next: sql_server_test_action

  - id: sql_server_test_action
    type: action
    action: kerberos.test_sql_server_connection
    next: postgres_test_prompt

  # Similar pattern for PostgreSQL...
```

---

## Testing Commands

```bash
# Run all Kerberos tests
cd wizard && uv run pytest services/kerberos/tests/ -v

# Test specific component
uv run pytest services/kerberos/tests/test_sql_connection.py -v

# Manual integration test
./wizard/wizard.py setup --service kerberos
```

## Commit Strategy

- Commit after each task passes tests
- Use conventional commits: `feat:`, `test:`, `refactor:`
- Reference design doc in commits