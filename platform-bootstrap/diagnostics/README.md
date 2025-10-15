# Diagnostic Tools

This directory contains diagnostic scripts that can be deployed to target environments for troubleshooting Kerberos and SQL Server authentication issues.

## Scripts for Production Use

These scripts are designed to be safe for use in production environments:

### `krb5-auth-test.sh`
Universal Kerberos authentication diagnostic tool. Works on host systems and inside containers.

**Usage:**
```bash
./krb5-auth-test.sh           # Full diagnostics
./krb5-auth-test.sh -q        # Quick mode
./krb5-auth-test.sh -j        # JSON output for automation
./krb5-auth-test.sh --help    # Show all options
```

**Features:**
- Detects environment (host/container/WSL/K8s)
- Validates Kerberos configuration
- Checks ticket validity and expiration
- Tests SQL Server authentication
- Provides actionable recommendations

### `diagnose-kerberos.sh`
Comprehensive Kerberos troubleshooting for Docker environments.

**Usage:**
```bash
./diagnose-kerberos.sh        # Run full diagnostics
```

**Features:**
- Container ticket validation
- Network connectivity tests
- Time synchronization checks
- Docker configuration validation

### `generate-diagnostic-context.sh`
Generates a comprehensive diagnostic report optimized for LLM analysis (ChatGPT, Claude, etc.)

**Usage:**
```bash
./generate-diagnostic-context.sh > diagnostic-report.md
# Then paste the report into your LLM with your question
```

**Features:**
- Self-contained context document
- All relevant system information
- Formatted for LLM consumption
- Includes troubleshooting hints

### `test-sql-direct.sh`
Direct SQL Server connection test using host-side Kerberos tickets.

**Usage:**
```bash
./test-sql-direct.sh <sql-server> <database>
```

**Features:**
- Tests Kerberos authentication to SQL Server
- Shows authentication method (Kerberos vs NTLM)
- Provides connection diagnostics

### `test-sql-simple.sh`
Containerized SQL Server test using shared Kerberos tickets.

**Usage:**
```bash
./test-sql-simple.sh
```

**Features:**
- Tests ticket sharing with containers
- Validates sidecar pattern
- Shows authentication flow

### `check-sql-spn.sh`
Checks SQL Server Service Principal Names (SPNs) configuration.

**Usage:**
```bash
./check-sql-spn.sh <sql-server>
```

**Features:**
- Validates SPN registration
- Checks for duplicate SPNs
- Provides fix recommendations

## Deployment to Target Environments

These scripts are designed to be portable:

1. **Single file deployment** - Each script is self-contained
2. **No dependencies** - Uses only standard Linux tools
3. **Safe execution** - Read-only operations, no system modifications
4. **Clear output** - Human and machine-readable results

## Environment Variables

Scripts respect these environment variables:

- `NO_COLOR=1` - Disable colored output
- `KRB5CCNAME` - Kerberos ticket cache location
- `KRB5_CONFIG` - Kerberos configuration file
- `KRB5_TRACE=/dev/stderr` - Enable Kerberos trace logging

## Output Formats

### Terminal Output
```
✓ Valid Kerberos ticket
✓ SQL Server connection successful
⚠ Ticket expires in less than 1 hour
```

### NO_COLOR Output
```
[PASS] Valid Kerberos ticket
[PASS] SQL Server connection successful
[WARN] Ticket expires in less than 1 hour
```

### JSON Output (with -j flag)
```json
{
  "ticket_valid": "true",
  "sql_auth": "success",
  "sql_auth_method": "KERBEROS"
}
```

## Troubleshooting Workflow

1. Start with quick diagnostics:
   ```bash
   ./krb5-auth-test.sh -q
   ```

2. If issues found, run full diagnostics:
   ```bash
   ./krb5-auth-test.sh -v
   ```

3. For LLM assistance, generate context:
   ```bash
   ./generate-diagnostic-context.sh > report.md
   ```

4. Test specific components:
   ```bash
   ./test-sql-direct.sh sqlserver01 TestDB
   ```

## Security Notes

- Scripts only read system state, never modify
- No credentials are stored or logged
- Safe for production use
- Output sanitized for sharing