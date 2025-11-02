# Database Health Checks Design

**Date:** 2025-11-01
**Status:** Approved for implementation

## Overview

Add automated health checks that verify database services are functional after installation. The wizard will run these checks automatically after standing up PostgreSQL and Pagila, using the postgres-test container to verify connectivity, authentication, and data accessibility.

## Problem Statement

Currently, the wizard assumes services are healthy if installation returns exit code 0, but doesn't verify:
- Cross-container network connectivity
- Authentication configuration works correctly
- Databases are queryable and contain expected data
- Test containers can access the databases they need to test

This creates a gap where services may appear to install successfully but are not actually functional.

## Goals

1. **Automatic verification:** Health checks run automatically after service installation
2. **Detailed reporting:** Success reports include database metrics (row counts, table counts, etc.)
3. **Non-blocking:** Failed health checks warn but don't block wizard progression
4. **Reusable:** Health check scripts can be run independently for manual testing
5. **Consistent:** Use existing diagnostic framework and formatting patterns

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Shell Scripts (Source of Truth)               │
│ - platform-infrastructure/tests/*.sh                    │
│ - Uses formatting library                               │
│ - Supports --quiet flag for wizard integration          │
│ - Can be run directly from command line                 │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ called by
                          │
┌─────────────────────────────────────────────────────────┐
│ Layer 2: Python Integration (Wizard)                    │
│ - wizard/utils/diagnostics.py                           │
│ - Wraps shell scripts                                   │
│ - Parses output into structured results                 │
│ - Integrates with existing diagnostic framework         │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ called by
                          │
┌─────────────────────────────────────────────────────────┐
│ Layer 3: Makefile Targets (Discoverability)            │
│ - platform-infrastructure/Makefile                      │
│ - make test-platform-postgres-connectivity              │
│ - make test-pagila-connectivity                         │
│ - make test-connectivity (runs all)                     │
└─────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Shell Test Scripts

#### test-platform-postgres-connectivity.sh

**Location:** `platform-infrastructure/tests/test-platform-postgres-connectivity.sh`

**Purpose:** Verify platform-postgres (core infrastructure database) is accessible from postgres-test container

**Tests performed:**
1. **Prerequisites:**
   - postgres-test container exists and is running
   - platform-postgres container exists and is running
   - Both containers on platform_network

2. **Authentication:**
   - Read credentials from `../platform-bootstrap/.env`
   - Use PGPASSWORD environment variable for auth

3. **Connectivity:**
   - Network: `ping platform-postgres`
   - Service: `pg_isready -h platform-postgres -U platform_admin`
   - Auth: `psql -c "SELECT 1"`

4. **Database health:**
   - Check for expected databases: airflow_db, openmetadata_db
   - Query: `SELECT current_database(), version()`
   - Count databases

**Output modes:**
- Default: Detailed output with all test results (uses formatting library)
- `--quiet`: Brief summary for wizard integration
  - Success: `✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5`
  - Failure: Exit code 1 with error message

**Exit codes:**
- 0: All tests passed
- 1: At least one test failed

#### test-pagila-connectivity.sh

**Location:** `platform-infrastructure/tests/test-pagila-connectivity.sh`

**Purpose:** Verify Pagila sample database is accessible from postgres-test container

**Tests performed:**
1. **Prerequisites:**
   - postgres-test container exists and is running
   - pagila-postgres container exists and is running
   - Both containers on platform_network

2. **Authentication:**
   - Check `../pagila/.env` for POSTGRES_PASSWORD
   - If empty/missing: use trust auth (no password)
   - If set: use password auth with PGPASSWORD

3. **Connectivity:**
   - Network: `ping pagila-postgres`
   - Service: `pg_isready -h pagila-postgres -U postgres`
   - Auth: `psql -c "SELECT 1"`

4. **Data validation:**
   - `SELECT COUNT(*) FROM actor` (expect 200)
   - `SELECT COUNT(*) FROM film` (expect 1000)
   - `SELECT COUNT(*) FROM rental` (verify > 0)
   - List all tables in pagila schema

**Output modes:**
- Default: Detailed output with all test results
- `--quiet`: Brief summary
  - Success: `✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals`
  - Failure: Exit code 1 with error message

**Exit codes:**
- 0: All tests passed
- 1: At least one test failed

**Common script patterns:**
- Source formatting library: `source "$(dirname "$0")/../../platform-bootstrap/lib/formatting.sh"`
- Use print_header, print_section, print_check for output
- Stop on first failure with clear error message
- Structured output: Prerequisites → Auth Config → Tests → Summary

### 2. Python Integration Layer

**Location:** `wizard/utils/diagnostics.py`

**New methods in ServiceDiagnostics class:**

```python
def verify_postgres_health(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
    """Verify platform-postgres health using postgres-test container.

    Runs test-platform-postgres-connectivity.sh with --quiet flag.

    Returns:
        {
            'healthy': bool,        # True if all tests passed
            'summary': str,         # Brief message (from --quiet output)
            'details': str,         # Full output from test script
            'error': str            # Error message if unhealthy
        }
    """

def verify_pagila_health(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
    """Verify Pagila health using postgres-test container.

    Returns same structure as verify_postgres_health.
    """
```

**Integration points:**

1. **wizard/services/base_platform/actions.py**
   - After successful PostgreSQL installation (~line 214)
   - Run verify_postgres_health()
   - Display summary or save diagnostics

2. **wizard/services/pagila/actions.py**
   - After successful Pagila installation (~line 54)
   - Run verify_pagila_health()
   - Display summary or save diagnostics

**Example integration:**

```python
if result.get('returncode') == 0:
    runner.display("✓ PostgreSQL started successfully")

    # Run health check
    runner.display("")
    runner.display("Verifying PostgreSQL health...")

    service_diag = ServiceDiagnostics(runner)
    health = service_diag.verify_postgres_health(ctx)

    if health['healthy']:
        runner.display(health['summary'])  # Detailed success message
    else:
        runner.display(f"⚠️  Health check failed: {health['error']}")

        # Save diagnostics
        collector = DiagnosticCollector()
        collector.record_failure('postgres', 'health_check', health['error'])
        log_file = collector.save_log()

        runner.display(f"💾 Diagnostics saved to: {log_file}")
        runner.display("   Continuing setup...")
```

### 3. Makefile Integration

**Location:** `platform-infrastructure/Makefile`

**New targets:**

```makefile
test-platform-postgres-connectivity: ## Test connectivity to platform-postgres using postgres-test
	@bash tests/test-platform-postgres-connectivity.sh

test-pagila-connectivity: ## Test connectivity to Pagila using postgres-test
	@bash tests/test-pagila-connectivity.sh

test-connectivity: test-platform-postgres-connectivity test-pagila-connectivity ## Run all connectivity tests
```

**Benefits:**
- Discoverable via `make help`
- Consistent with existing Makefile operations
- Easy to run manually: `make -C platform-infrastructure test-pagila-connectivity`
- Can be integrated into CI/CD pipelines

## Error Handling

### Edge Cases

1. **postgres-test container doesn't exist:**
   - Error message: "postgres-test container not found - run wizard to create test containers"
   - Exit gracefully with exit code 1
   - Wizard displays error but continues

2. **Target database not running:**
   - Skip prerequisite checks
   - Clear message: "pagila-postgres not running - skipping health check"
   - Return healthy=False but don't save diagnostics (expected state)

3. **Network issues:**
   - Distinguish between:
     - Container not connected to network
     - Network doesn't exist
   - Suggest: `docker network connect platform_network postgres-test`

4. **Authentication failures:**
   - Detect failure type:
     - Wrong password: "Authentication failed - check POSTGRES_PASSWORD in .env"
     - Trust not configured: "Trust auth failed - check pg_hba.conf"
   - Provide specific suggestions based on error

5. **Partial data:**
   - Example: actor table has 150 rows instead of 200
   - Still mark healthy=True
   - Add warning in detailed output: "⚠️ Warning: Expected 200 actors, found 150"
   - Don't treat as failure unless data is completely missing

### Wizard Behavior

**On success:**
```
✓ Pagila installed successfully

Verifying Pagila health...
✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals
```

**On failure (non-blocking):**
```
✓ Pagila installed successfully

Verifying Pagila health...
⚠️  Health check failed: Cannot connect to pagila-postgres
💾 Diagnostics saved to: diagnostic_20251101_143022.log
   Continuing setup...
```

## Testing Strategy

### Unit Tests

**Location:** `wizard/utils/tests/test_diagnostics.py`

**Coverage:**
- Test Python wrappers (verify_postgres_health, verify_pagila_health)
- Mock shell script execution
- Verify correct parsing of output
- Test error handling for various failure modes

### Integration Tests

**Location:** `platform-infrastructure/tests/`

**Coverage:**
- Test scripts work with actual containers
- Verify output format consistency
- Test both --quiet and default modes
- Verify exit codes are correct
- Test auth detection logic (trust vs password)

### Acceptance Criteria

- [ ] Health checks run automatically after installation
- [ ] Detailed output shows database metrics (row counts, versions, etc.)
- [ ] Failed checks don't block wizard progression
- [ ] Diagnostics saved to timestamped files on failure
- [ ] Scripts can be run manually from command line
- [ ] Makefile targets work independently
- [ ] Tests use formatting library for consistent output
- [ ] Auth detection works for both trust and password methods
- [ ] Clear error messages for common failure scenarios

## Future Enhancements

1. **SQL Server connectivity tests:**
   - Add `test-sqlserver-connectivity.sh` when we have a SQL Server target
   - Use sqlcmd-test container to verify connectivity

2. **Performance metrics:**
   - Add query timing to health checks
   - Alert if queries take longer than expected

3. **Scheduled health checks:**
   - Add cron jobs or systemd timers for periodic checks
   - Send notifications on health degradation

4. **Health check API:**
   - Add REST endpoint for health status
   - Allow external monitoring systems to query

## Implementation Order

1. **Phase 1: Shell scripts**
   - Create test-platform-postgres-connectivity.sh
   - Create test-pagila-connectivity.sh
   - Test manually to verify output and behavior

2. **Phase 2: Makefile integration**
   - Add targets to platform-infrastructure/Makefile
   - Test make commands work

3. **Phase 3: Python wrappers**
   - Add verify_postgres_health() to diagnostics.py
   - Add verify_pagila_health() to diagnostics.py
   - Add unit tests

4. **Phase 4: Wizard integration**
   - Integrate into base_platform/actions.py
   - Integrate into pagila/actions.py
   - Test end-to-end wizard flow

5. **Phase 5: Documentation**
   - Update platform-infrastructure/README.md
   - Update wizard documentation
   - Add examples to CLAUDE.md if needed

## Success Metrics

- Health checks catch database connectivity issues before user discovers them
- Diagnostic files provide actionable troubleshooting information
- Users can manually verify service health with simple make commands
- Zero false positives (healthy services always pass checks)
- Minimal false negatives (unhealthy services detected >95% of time)
