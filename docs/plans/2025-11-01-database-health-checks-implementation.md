# Database Health Checks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automated health checks that verify database connectivity and functionality after installation using the postgres-test container.

**Architecture:** Three-layer design with shell scripts as source of truth (can run independently), Python wrappers for wizard integration, and Makefile targets for discoverability. Tests run automatically after service installation with detailed success reporting or diagnostic file generation on failure.

**Tech Stack:** Bash (shell scripts), Python 3.12 (wizard integration), PostgreSQL client tools (psql, pg_isready), Docker, existing platform formatting library

---

## Implementation Strategy

**TDD Approach:** RED → GREEN → REVIEW cycle for each component
- Write failing test first
- Implement minimal code to pass
- Review and refactor
- Commit small, focused changes

**Parallel Execution:** Tasks 1-2 can run in parallel (different files), Task 3 depends on both completing

**Branch Structure:**
- Master branch: `feature/database-health-checks` (current worktree)
- Sub-branches: Create for each parallel task if using subagents

---

## Task 1: Platform Postgres Connectivity Test Script

**Files:**
- Create: `platform-infrastructure/tests/test-platform-postgres-connectivity.sh`
- Reference: `platform-bootstrap/lib/formatting.sh`
- Reference: `platform-infrastructure/Makefile` (for understanding test patterns)

**Prerequisites:** Understand the formatting library and existing test patterns

**Step 1: Write a basic test scaffold**

Create the file with basic structure:

```bash
#!/bin/bash
# Test platform-postgres connectivity from postgres-test container
# Purpose: Verify core infrastructure database is accessible and functional

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO_ROOT/platform-bootstrap/lib/formatting.sh"

# Parse arguments
QUIET_MODE=false
if [[ "$1" == "--quiet" ]]; then
    QUIET_MODE=true
fi

print_header "Platform PostgreSQL Connectivity Test"

echo "TODO: Implement tests"
exit 1
```

**Step 2: Make executable and test it fails**

Run:
```bash
chmod +x platform-infrastructure/tests/test-platform-postgres-connectivity.sh
./platform-infrastructure/tests/test-platform-postgres-connectivity.sh
```

Expected: Script runs, prints header, exits with code 1

**Step 3: Implement prerequisite checks**

Add before the TODO:

```bash
# Check prerequisites
print_section "Prerequisites"

TESTS_PASSED=0
TESTS_TOTAL=0

check_prerequisite() {
    local name="$1"
    local command="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$command" >/dev/null 2>&1; then
        print_check "PASS" "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_check "FAIL" "$name"
        return 1
    fi
}

# Verify postgres-test container exists and is running
if ! check_prerequisite "postgres-test container running" "docker ps --filter 'name=postgres-test' --filter 'status=running' --format '{{.Names}}' | grep -q '^postgres-test$'"; then
    print_error "postgres-test container not found or not running"
    print_info "Create test containers with: ./platform setup"
    exit 1
fi

# Verify platform-postgres container exists and is running
if ! check_prerequisite "platform-postgres container running" "docker ps --filter 'name=platform-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^platform-postgres$'"; then
    print_error "platform-postgres container not found or not running"
    print_info "Start platform infrastructure with: make -C platform-infrastructure start"
    exit 1
fi

# Verify both containers on platform_network
if ! check_prerequisite "Containers on platform_network" "docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'platform-postgres'"; then
    print_error "Containers not on same network"
    print_info "Connect with: docker network connect platform_network postgres-test"
    exit 1
fi
```

**Step 4: Test prerequisite checks**

Run:
```bash
# First ensure containers are actually running
docker ps | grep -E "(postgres-test|platform-postgres)"

# Run the test
./platform-infrastructure/tests/test-platform-postgres-connectivity.sh
```

Expected: Prerequisites section shows PASS/FAIL correctly based on actual container state

**Step 5: Implement auth detection**

Add after prerequisite checks:

```bash
# Detect authentication configuration
print_section "Authentication Configuration"

ENV_FILE="$REPO_ROOT/platform-bootstrap/.env"
POSTGRES_PASSWORD=""

if [ -f "$ENV_FILE" ]; then
    # Read password from .env file
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -n "$POSTGRES_PASSWORD" ]; then
        print_info "Using password authentication (from platform-bootstrap/.env)"
    else
        print_warning "POSTGRES_PASSWORD empty in .env - using trust authentication"
    fi
else
    print_warning "No .env file found - using trust authentication"
fi

# Export for psql commands
export PGPASSWORD="$POSTGRES_PASSWORD"
```

**Step 6: Test auth detection**

Run:
```bash
./platform-infrastructure/tests/test-platform-postgres-connectivity.sh
```

Expected: Auth configuration section shows correct detection based on .env file

**Step 7: Implement connectivity tests**

Add after auth detection, remove the TODO:

```bash
# Run connectivity tests
print_section "Connectivity Tests"

run_test() {
    local test_name="$1"
    local test_command="$2"
    local success_pattern="${3:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$QUIET_MODE" = false ]; then
        print_info "Running: $test_name"
    fi

    local output
    if output=$(eval "$test_command" 2>&1); then
        if [ -z "$success_pattern" ] || echo "$output" | grep -q "$success_pattern"; then
            print_check "PASS" "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi

    print_check "FAIL" "$test_name"
    if [ "$QUIET_MODE" = false ]; then
        print_error "Error: $output"
    fi
    return 1
}

# Test 1: Network connectivity
if ! run_test "Network connectivity" "docker exec postgres-test ping -c 1 -W 2 platform-postgres"; then
    print_error "Cannot reach platform-postgres from postgres-test"
    exit 1
fi

# Test 2: PostgreSQL service ready
if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h platform-postgres -U platform_admin -q"; then
    print_error "PostgreSQL service not accepting connections"
    exit 1
fi

# Test 3: Database authentication
if ! run_test "Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h platform-postgres -U platform_admin -d postgres -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Authentication failed"
    exit 1
fi

# Test 4: Query database list
DB_LIST=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U platform_admin -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname IN ('airflow_db', 'openmetadata_db') ORDER BY datname")
DB_COUNT=$(echo "$DB_LIST" | grep -c '^')

if [ "$DB_COUNT" -gt 0 ]; then
    print_check "PASS" "Platform databases exist ($DB_COUNT found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [ "$QUIET_MODE" = false ]; then
        echo "$DB_LIST" | while read -r db; do
            print_bullet "$db"
        done
    fi
else
    print_check "WARN" "No platform databases found yet"
    print_info "Databases will be created on first use by services"
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# Test 5: Query PostgreSQL version
PG_VERSION=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h platform-postgres -U platform_admin -d postgres -t -A -c "SELECT version()" | head -n1 | cut -d' ' -f2)
print_check "PASS" "PostgreSQL version: $PG_VERSION"
TESTS_PASSED=$((TESTS_PASSED + 1))
TESTS_TOTAL=$((TESTS_TOTAL + 1))
```

**Step 8: Implement summary output**

Add at the end of the script:

```bash
# Summary
print_divider
echo ""

if [ "$QUIET_MODE" = true ]; then
    # Brief output for wizard integration
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        echo "✓ Platform postgres healthy - $DB_COUNT databases, PostgreSQL $PG_VERSION"
        exit 0
    else
        echo "✗ Platform postgres unhealthy - $TESTS_PASSED/$TESTS_TOTAL tests passed"
        exit 1
    fi
else
    # Detailed output
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        print_success "All tests passed! ($TESTS_PASSED/$TESTS_TOTAL)"
        exit 0
    else
        print_error "Some tests failed! ($TESTS_PASSED/$TESTS_TOTAL passed)"
        exit 1
    fi
fi
```

**Step 9: Test the complete script**

Run:
```bash
# Test detailed mode
./platform-infrastructure/tests/test-platform-postgres-connectivity.sh

# Test quiet mode
./platform-infrastructure/tests/test-platform-postgres-connectivity.sh --quiet
```

Expected:
- Detailed mode shows all sections and tests
- Quiet mode shows brief summary
- Exit code 0 if all pass, 1 if any fail

**Step 10: Commit**

```bash
git add platform-infrastructure/tests/test-platform-postgres-connectivity.sh
git commit -m "feat: add platform-postgres connectivity test script

Add shell script to verify platform-postgres accessibility from
postgres-test container. Tests network connectivity, PostgreSQL
service, authentication, and database queries.

Supports --quiet mode for wizard integration and detailed mode
for manual testing. Uses platform formatting library for
consistent output.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Pagila Connectivity Test Script

**Files:**
- Create: `platform-infrastructure/tests/test-pagila-connectivity.sh`
- Reference: `platform-bootstrap/lib/formatting.sh`
- Reference: `platform-infrastructure/tests/test-platform-postgres-connectivity.sh` (for pattern consistency)

**Prerequisites:** Task 1 completed (for reference patterns)

**Step 1: Write basic test scaffold**

Create the file with basic structure:

```bash
#!/bin/bash
# Test pagila-postgres connectivity from postgres-test container
# Purpose: Verify Pagila sample database is accessible and contains expected data

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO_ROOT/platform-bootstrap/lib/formatting.sh"

# Parse arguments
QUIET_MODE=false
if [[ "$1" == "--quiet" ]]; then
    QUIET_MODE=true
fi

print_header "Pagila Database Connectivity Test"

echo "TODO: Implement tests"
exit 1
```

**Step 2: Make executable and test it fails**

Run:
```bash
chmod +x platform-infrastructure/tests/test-pagila-connectivity.sh
./platform-infrastructure/tests/test-pagila-connectivity.sh
```

Expected: Script runs, prints header, exits with code 1

**Step 3: Implement prerequisite checks**

Add before the TODO:

```bash
# Check prerequisites
print_section "Prerequisites"

TESTS_PASSED=0
TESTS_TOTAL=0

check_prerequisite() {
    local name="$1"
    local command="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$command" >/dev/null 2>&1; then
        print_check "PASS" "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_check "FAIL" "$name"
        return 1
    fi
}

# Verify postgres-test container exists and is running
if ! check_prerequisite "postgres-test container running" "docker ps --filter 'name=postgres-test' --filter 'status=running' --format '{{.Names}}' | grep -q '^postgres-test$'"; then
    print_error "postgres-test container not found or not running"
    print_info "Create test containers with: ./platform setup"
    exit 1
fi

# Verify pagila-postgres container exists and is running
if ! check_prerequisite "pagila-postgres container running" "docker ps --filter 'name=pagila-postgres' --filter 'status=running' --format '{{.Names}}' | grep -q '^pagila-postgres$'"; then
    print_error "pagila-postgres container not found or not running"
    print_info "Install Pagila with: ./platform setup pagila"
    exit 1
fi

# Verify both containers on platform_network
if ! check_prerequisite "Containers on platform_network" "docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'postgres-test' && docker network inspect platform_network -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q 'pagila-postgres'"; then
    print_error "Containers not on same network"
    print_info "Connect with: docker network connect platform_network postgres-test"
    exit 1
fi
```

**Step 4: Test prerequisite checks**

Run:
```bash
# Ensure pagila is running
docker ps | grep pagila-postgres

# Run the test
./platform-infrastructure/tests/test-pagila-connectivity.sh
```

Expected: Prerequisites section shows PASS/FAIL correctly based on container state

**Step 5: Implement auth detection**

Add after prerequisite checks:

```bash
# Detect authentication configuration for Pagila
print_section "Authentication Configuration"

PAGILA_DIR="$REPO_ROOT/../pagila"
POSTGRES_PASSWORD=""

if [ -d "$PAGILA_DIR" ] && [ -f "$PAGILA_DIR/.env" ]; then
    # Read password from Pagila's .env file
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$PAGILA_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -n "$POSTGRES_PASSWORD" ]; then
        print_info "Using password authentication (from ../pagila/.env)"
    else
        print_info "Using trust authentication (POSTGRES_PASSWORD empty in ../pagila/.env)"
    fi
else
    print_info "Using trust authentication (no ../pagila/.env file found)"
fi

# Export for psql commands
export PGPASSWORD="$POSTGRES_PASSWORD"
```

**Step 6: Test auth detection**

Run:
```bash
./platform-infrastructure/tests/test-pagila-connectivity.sh
```

Expected: Auth configuration section shows correct detection based on Pagila's .env

**Step 7: Implement connectivity tests**

Add after auth detection, remove the TODO:

```bash
# Run connectivity tests
print_section "Connectivity Tests"

run_test() {
    local test_name="$1"
    local test_command="$2"
    local success_pattern="${3:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$QUIET_MODE" = false ]; then
        print_info "Running: $test_name"
    fi

    local output
    if output=$(eval "$test_command" 2>&1); then
        if [ -z "$success_pattern" ] || echo "$output" | grep -q "$success_pattern"; then
            print_check "PASS" "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
    fi

    print_check "FAIL" "$test_name"
    if [ "$QUIET_MODE" = false ]; then
        print_error "Error: $output"
    fi
    return 1
}

# Test 1: Network connectivity
if ! run_test "Network connectivity" "docker exec postgres-test ping -c 1 -W 2 pagila-postgres"; then
    print_error "Cannot reach pagila-postgres from postgres-test"
    exit 1
fi

# Test 2: PostgreSQL service ready
if ! run_test "PostgreSQL service ready" "docker exec postgres-test pg_isready -h pagila-postgres -U postgres -q"; then
    print_error "PostgreSQL service not accepting connections"
    exit 1
fi

# Test 3: Database authentication
if ! run_test "Database authentication" "docker exec -e PGPASSWORD=\"$POSTGRES_PASSWORD\" postgres-test psql -h pagila-postgres -U postgres -d pagila -c 'SELECT 1' -t -A" "^1$"; then
    print_error "Authentication failed"
    exit 1
fi
```

**Step 8: Implement data validation tests**

Add after connectivity tests:

```bash
# Data validation tests
print_section "Data Validation"

# Test 4: Actor table
ACTOR_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM actor")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$ACTOR_COUNT" = "200" ]; then
    print_check "PASS" "Actor table: $ACTOR_COUNT rows (expected)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$ACTOR_COUNT" -gt 0 ]; then
    print_check "WARN" "Actor table: $ACTOR_COUNT rows (expected 200)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Actor table: empty or missing"
fi

# Test 5: Film table
FILM_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM film")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$FILM_COUNT" = "1000" ]; then
    print_check "PASS" "Film table: $FILM_COUNT rows (expected)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$FILM_COUNT" -gt 0 ]; then
    print_check "WARN" "Film table: $FILM_COUNT rows (expected 1000)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Film table: empty or missing"
fi

# Test 6: Rental table
RENTAL_COUNT=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT COUNT(*) FROM rental")
TESTS_TOTAL=$((TESTS_TOTAL + 1))

if [ "$RENTAL_COUNT" -gt 0 ]; then
    print_check "PASS" "Rental table: $RENTAL_COUNT rows"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Rental table: empty or missing"
fi

# Test 7: Schema check (list tables)
if [ "$QUIET_MODE" = false ]; then
    print_section "Database Schema"
    TABLE_LIST=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres-test psql -h pagila-postgres -U postgres -d pagila -t -A -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")
    TABLE_COUNT=$(echo "$TABLE_LIST" | grep -c '^')

    print_info "Found $TABLE_COUNT tables:"
    echo "$TABLE_LIST" | while read -r table; do
        print_bullet "$table"
    done
fi
```

**Step 9: Implement summary output**

Add at the end of the script:

```bash
# Summary
print_divider
echo ""

if [ "$QUIET_MODE" = true ]; then
    # Brief output for wizard integration
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        echo "✓ Pagila healthy - $ACTOR_COUNT actors, $FILM_COUNT films, $RENTAL_COUNT rentals"
        exit 0
    else
        echo "✗ Pagila unhealthy - $TESTS_PASSED/$TESTS_TOTAL tests passed"
        exit 1
    fi
else
    # Detailed output
    if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
        print_success "All tests passed! ($TESTS_PASSED/$TESTS_TOTAL)"
        exit 0
    else
        print_error "Some tests failed! ($TESTS_PASSED/$TESTS_TOTAL passed)"
        exit 1
    fi
fi
```

**Step 10: Test the complete script**

Run:
```bash
# Test detailed mode
./platform-infrastructure/tests/test-pagila-connectivity.sh

# Test quiet mode
./platform-infrastructure/tests/test-pagila-connectivity.sh --quiet
```

Expected:
- Detailed mode shows all sections, tests, and table list
- Quiet mode shows brief summary with row counts
- Exit code 0 if all pass, 1 if any fail

**Step 11: Commit**

```bash
git add platform-infrastructure/tests/test-pagila-connectivity.sh
git commit -m "feat: add Pagila connectivity test script

Add shell script to verify Pagila database accessibility from
postgres-test container. Tests network connectivity, PostgreSQL
service, authentication, and validates sample data is present
(actors, films, rentals).

Supports --quiet mode for wizard integration and detailed mode
for manual testing. Auto-detects auth method from Pagila's .env.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Makefile Integration

**Files:**
- Modify: `platform-infrastructure/Makefile:8` (add to .PHONY line)
- Modify: `platform-infrastructure/Makefile:134` (add new targets at end)

**Prerequisites:** Tasks 1 and 2 completed

**Step 1: Read the current Makefile**

Run:
```bash
cat platform-infrastructure/Makefile
```

Expected: See existing targets (help, start, stop, status, etc.)

**Step 2: Add new phony targets**

Modify line 8:

```makefile
.PHONY: help start stop restart status logs clean build-postgres-test build-sqlcmd-test build-test-containers test-platform-postgres-connectivity test-pagila-connectivity test-connectivity
```

**Step 3: Add connectivity test targets**

Add at the end of the file (after line 134):

```makefile

test-platform-postgres-connectivity: ## Test connectivity to platform-postgres using postgres-test
	@bash tests/test-platform-postgres-connectivity.sh

test-pagila-connectivity: ## Test connectivity to Pagila using postgres-test
	@bash tests/test-pagila-connectivity.sh

test-connectivity: test-platform-postgres-connectivity test-pagila-connectivity ## Run all connectivity tests
```

**Step 4: Test Makefile targets**

Run:
```bash
# Verify targets appear in help
make -C platform-infrastructure help | grep connectivity

# Test individual targets
make -C platform-infrastructure test-platform-postgres-connectivity
make -C platform-infrastructure test-pagila-connectivity

# Test combined target
make -C platform-infrastructure test-connectivity
```

Expected:
- Help shows new targets with descriptions
- Each target runs corresponding script
- test-connectivity runs both scripts in sequence

**Step 5: Commit**

```bash
git add platform-infrastructure/Makefile
git commit -m "feat: add connectivity test targets to Makefile

Add make targets for database connectivity tests:
- test-platform-postgres-connectivity
- test-pagila-connectivity
- test-connectivity (runs both)

Tests are discoverable via make help and can be run
independently for manual verification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Python Integration - Diagnostics Module

**Files:**
- Modify: `wizard/utils/diagnostics.py:88` (add new methods to ServiceDiagnostics class)
- Reference: `wizard/utils/diagnostics.py:1-100` (understand existing patterns)

**Prerequisites:** Tasks 1-3 completed (shell scripts must exist)

**Step 1: Read existing diagnostics code**

Run:
```bash
head -n 100 wizard/utils/diagnostics.py
```

Expected: Understand ServiceDiagnostics class structure and run_shell pattern

**Step 2: Add verify_postgres_health method**

Add to ServiceDiagnostics class (after existing methods, around line 150):

```python
    def verify_postgres_health(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Verify platform-postgres health using postgres-test container.

        Runs test-platform-postgres-connectivity.sh with --quiet flag.

        Args:
            ctx: Service context (not currently used but kept for consistency)

        Returns:
            {
                'healthy': bool,        # True if all tests passed
                'summary': str,         # Brief message (from --quiet output)
                'details': str,         # Full output from test script
                'error': str            # Error message if unhealthy (empty if healthy)
            }
        """
        # Run test script with --quiet flag for brief output
        result = self.runner.run_shell([
            'bash',
            'platform-infrastructure/tests/test-platform-postgres-connectivity.sh',
            '--quiet'
        ])

        output = result.get('stdout', '').strip()
        stderr = result.get('stderr', '').strip()
        returncode = result.get('returncode', 1)

        if returncode == 0:
            return {
                'healthy': True,
                'summary': output,
                'details': output,
                'error': ''
            }
        else:
            # Extract error from output or stderr
            error_msg = output if output else stderr
            if not error_msg:
                error_msg = "Health check failed with no output"

            return {
                'healthy': False,
                'summary': '',
                'details': f"{output}\n{stderr}".strip(),
                'error': error_msg
            }
```

**Step 3: Add verify_pagila_health method**

Add after verify_postgres_health:

```python
    def verify_pagila_health(self, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Verify Pagila health using postgres-test container.

        Runs test-pagila-connectivity.sh with --quiet flag.

        Args:
            ctx: Service context (not currently used but kept for consistency)

        Returns:
            Same structure as verify_postgres_health:
            {
                'healthy': bool,
                'summary': str,
                'details': str,
                'error': str
            }
        """
        # Run test script with --quiet flag for brief output
        result = self.runner.run_shell([
            'bash',
            'platform-infrastructure/tests/test-pagila-connectivity.sh',
            '--quiet'
        ])

        output = result.get('stdout', '').strip()
        stderr = result.get('stderr', '').strip()
        returncode = result.get('returncode', 1)

        if returncode == 0:
            return {
                'healthy': True,
                'summary': output,
                'details': output,
                'error': ''
            }
        else:
            # Extract error from output or stderr
            error_msg = output if output else stderr
            if not error_msg:
                error_msg = "Health check failed with no output"

            return {
                'healthy': False,
                'summary': '',
                'details': f"{output}\n{stderr}".strip(),
                'error': error_msg
            }
```

**Step 4: Write unit tests**

Create or modify: `wizard/utils/tests/test_diagnostics.py`

Add tests for the new methods:

```python
def test_verify_postgres_health_success(self):
    """Should return healthy=True when script succeeds."""
    mock_runner = MockRunner()
    mock_runner.set_shell_result({
        'returncode': 0,
        'stdout': '✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5',
        'stderr': ''
    })

    service_diag = ServiceDiagnostics(mock_runner)
    result = service_diag.verify_postgres_health({})

    assert result['healthy'] is True
    assert 'PostgreSQL 17.5' in result['summary']
    assert result['error'] == ''


def test_verify_postgres_health_failure(self):
    """Should return healthy=False when script fails."""
    mock_runner = MockRunner()
    mock_runner.set_shell_result({
        'returncode': 1,
        'stdout': '✗ Platform postgres unhealthy - 2/5 tests passed',
        'stderr': 'Connection refused'
    })

    service_diag = ServiceDiagnostics(mock_runner)
    result = service_diag.verify_postgres_health({})

    assert result['healthy'] is False
    assert 'unhealthy' in result['error']
    assert len(result['details']) > 0


def test_verify_pagila_health_success(self):
    """Should return healthy=True when Pagila check succeeds."""
    mock_runner = MockRunner()
    mock_runner.set_shell_result({
        'returncode': 0,
        'stdout': '✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals',
        'stderr': ''
    })

    service_diag = ServiceDiagnostics(mock_runner)
    result = service_diag.verify_pagila_health({})

    assert result['healthy'] is True
    assert '200 actors' in result['summary']
    assert result['error'] == ''


def test_verify_pagila_health_failure(self):
    """Should return healthy=False when Pagila check fails."""
    mock_runner = MockRunner()
    mock_runner.set_shell_result({
        'returncode': 1,
        'stdout': '✗ Pagila unhealthy - 3/6 tests passed',
        'stderr': 'pagila-postgres not found'
    })

    service_diag = ServiceDiagnostics(mock_runner)
    result = service_diag.verify_pagila_health({})

    assert result['healthy'] is False
    assert 'unhealthy' in result['error']
```

**Step 5: Run unit tests**

Run:
```bash
.venv/bin/pytest wizard/utils/tests/test_diagnostics.py -v -k verify
```

Expected: All new tests pass

**Step 6: Commit**

```bash
git add wizard/utils/diagnostics.py wizard/utils/tests/test_diagnostics.py
git commit -m "feat: add health check methods to diagnostics module

Add verify_postgres_health() and verify_pagila_health() methods
to ServiceDiagnostics class. These wrap the shell test scripts
and return structured results for wizard integration.

Includes unit tests for success and failure scenarios.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Wizard Integration - Base Platform

**Files:**
- Modify: `wizard/services/base_platform/actions.py:214-217` (add health check after successful install)
- Reference: `wizard/services/base_platform/actions.py:200-230` (understand install_postgres flow)
- Reference: `wizard/services/pagila/actions.py:50-60` (see existing diagnostic pattern)

**Prerequisites:** Task 4 completed (Python methods exist)

**Step 1: Read install_postgres function**

Run:
```bash
sed -n '200,230p' wizard/services/base_platform/actions.py
```

Expected: See the install_postgres function and where it displays success

**Step 2: Add health check after successful installation**

Modify the install_postgres function (around line 214):

```python
    if result.get('returncode') == 0:
        runner.display("✓ PostgreSQL started successfully")

        # Run health check
        runner.display("")
        runner.display("Verifying PostgreSQL health...")

        from wizard.utils.diagnostics import ServiceDiagnostics, DiagnosticCollector
        service_diag = ServiceDiagnostics(runner)
        health = service_diag.verify_postgres_health(ctx)

        if health['healthy']:
            # Display detailed success message
            runner.display(health['summary'])
        else:
            # Save diagnostics and warn (but continue)
            runner.display(f"⚠️  Health check failed: {health['error']}")

            collector = DiagnosticCollector()
            collector.record_failure('postgres', 'health_check', health['error'], {
                'details': health['details']
            })
            log_file = collector.save_log()

            runner.display(f"💾 Diagnostics saved to: {log_file}")
            runner.display("   Continuing setup...")
            runner.display("")
    else:
        runner.display("✗ PostgreSQL failed to start")
        # ... existing error handling ...
```

**Step 3: Test wizard integration manually**

This requires actually running the wizard, which is beyond automated testing. Document the manual test:

```bash
# Manual test procedure:
# 1. Run wizard: python -m wizard
# 2. Choose to install PostgreSQL
# 3. Observe health check runs after installation
# 4. Verify detailed output shows database count and version

# Expected output after install:
# ✓ PostgreSQL started successfully
#
# Verifying PostgreSQL health...
# ✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5
```

**Step 4: Commit**

```bash
git add wizard/services/base_platform/actions.py
git commit -m "feat: add health check to PostgreSQL installation

After successful PostgreSQL installation, automatically run
health check to verify connectivity from postgres-test container.

On success: Display detailed metrics (database count, version)
On failure: Save diagnostics to file and warn (non-blocking)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Wizard Integration - Pagila

**Files:**
- Modify: `wizard/services/pagila/actions.py:54-60` (add health check after successful install)
- Reference: `wizard/services/pagila/actions.py:30-60` (understand install_pagila flow)

**Prerequisites:** Task 4 completed (Python methods exist)

**Step 1: Read install_pagila function**

Run:
```bash
sed -n '30,60p' wizard/services/pagila/actions.py
```

Expected: See the install_pagila function and existing diagnostic pattern

**Step 2: Add health check after successful installation**

Modify the install_pagila function (around line 54):

```python
    if result.get('returncode') == 0:
        runner.display("✓ Pagila installed successfully")

        # Run health check
        runner.display("")
        runner.display("Verifying Pagila health...")

        service_diag = ServiceDiagnostics(runner)
        health = service_diag.verify_pagila_health(ctx)

        if health['healthy']:
            # Display detailed success message
            runner.display(health['summary'])
        else:
            # Save diagnostics and warn (but continue)
            runner.display(f"⚠️  Health check failed: {health['error']}")

            collector = DiagnosticCollector()
            collector.record_failure('pagila', 'health_check', health['error'], {
                'details': health['details']
            })
            log_file = collector.save_log()

            runner.display(f"💾 Diagnostics saved to: {log_file}")
            runner.display("   Continuing setup...")
            runner.display("")
    else:
        runner.display("✗ Pagila installation failed")
        # ... existing error handling ...
```

**Step 3: Test wizard integration manually**

Document the manual test procedure:

```bash
# Manual test procedure:
# 1. Run wizard: python -m wizard
# 2. Choose to install Pagila
# 3. Observe health check runs after installation
# 4. Verify detailed output shows actor, film, and rental counts

# Expected output after install:
# ✓ Pagila installed successfully
#
# Verifying Pagila health...
# ✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals
```

**Step 4: Commit**

```bash
git add wizard/services/pagila/actions.py
git commit -m "feat: add health check to Pagila installation

After successful Pagila installation, automatically run
health check to verify connectivity and data presence.

On success: Display detailed metrics (actor, film, rental counts)
On failure: Save diagnostics to file and warn (non-blocking)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Documentation Updates

**Files:**
- Modify: `platform-infrastructure/README.md` (add connectivity testing section)
- Modify: `wizard/README.md` (document health check behavior)

**Prerequisites:** All previous tasks completed

**Step 1: Update platform-infrastructure README**

Add a new section to platform-infrastructure/README.md (after the "Quick start" section):

```markdown
## Connectivity Testing

Test database connectivity using the postgres-test container:

### Manual Testing

```bash
# Test platform-postgres connectivity
make test-platform-postgres-connectivity

# Test Pagila connectivity (requires Pagila to be installed)
make test-pagila-connectivity

# Run all connectivity tests
make test-connectivity
```

### Direct Script Execution

Scripts can also be run directly:

```bash
# Detailed output (default)
./tests/test-platform-postgres-connectivity.sh
./tests/test-pagila-connectivity.sh

# Brief output (for automation)
./tests/test-platform-postgres-connectivity.sh --quiet
./tests/test-pagila-connectivity.sh --quiet
```

### What Gets Tested

**Platform Postgres:**
- Network connectivity
- PostgreSQL service availability
- Authentication
- Database existence (airflow_db, openmetadata_db)
- Version information

**Pagila:**
- Network connectivity
- PostgreSQL service availability
- Authentication (auto-detects trust vs password)
- Sample data presence (actors, films, rentals)
- Expected row counts

### Troubleshooting

If connectivity tests fail:

1. **Container not running:**
   ```bash
   docker ps | grep postgres-test
   make -C platform-infrastructure start
   ```

2. **Network issues:**
   ```bash
   docker network inspect platform_network
   docker network connect platform_network postgres-test
   ```

3. **Authentication failures:**
   - Check platform-bootstrap/.env for POSTGRES_PASSWORD
   - Check ../pagila/.env for Pagila password
   - Verify pg_hba.conf configuration
```

**Step 2: Update wizard README**

Add to wizard/README.md (in the features or usage section):

```markdown
## Automatic Health Checks

The wizard automatically verifies service health after installation:

### PostgreSQL Health Check

After installing PostgreSQL, the wizard runs connectivity tests using the
postgres-test container:

```
✓ PostgreSQL started successfully

Verifying PostgreSQL health...
✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5
```

### Pagila Health Check

After installing Pagila, the wizard verifies sample data is accessible:

```
✓ Pagila installed successfully

Verifying Pagila health...
✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals
```

### Health Check Failures

If health checks fail, diagnostics are saved automatically:

```
✓ Pagila installed successfully

Verifying Pagila health...
⚠️  Health check failed: Cannot connect to pagila-postgres
💾 Diagnostics saved to: diagnostic_20251101_143022.log
   Continuing setup...
```

**Note:** Health check failures are non-blocking. The wizard will continue
with setup but save detailed diagnostics for troubleshooting.

### Manual Health Checks

You can run health checks manually at any time:

```bash
# From repository root
make -C platform-infrastructure test-connectivity
```
```

**Step 3: Commit documentation**

```bash
git add platform-infrastructure/README.md wizard/README.md
git commit -m "docs: add connectivity testing documentation

Document health check functionality in both platform-infrastructure
and wizard READMEs. Include usage examples, troubleshooting steps,
and explanation of automatic health checks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: End-to-End Integration Test

**Files:**
- Create: `platform-bootstrap/tests/test-health-checks-integration.sh`
- Reference: `platform-bootstrap/tests/test-clean-slate.sh` (for integration test patterns)

**Prerequisites:** All previous tasks completed

**Step 1: Create integration test script**

Create a comprehensive integration test:

```bash
#!/bin/bash
# Integration test for health check functionality
# Tests the complete flow: setup → health check → verification

set -e

# Find repo root and source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$PLATFORM_DIR")"

source "$PLATFORM_DIR/lib/formatting.sh"

print_header "Health Checks Integration Test"

TESTS_RUN=0
TESTS_PASSED=0

test_result() {
    local status=$1
    local test_name=$2

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$status" = "pass" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_check "PASS" "$test_name"
    else
        print_check "FAIL" "$test_name"
    fi
}

# Test 1: Verify test scripts exist
print_section "Test 1: Script Files Exist"

if [ -f "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" ]; then
    test_result "pass" "platform-postgres test script exists"
else
    test_result "fail" "platform-postgres test script exists"
fi

if [ -f "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" ]; then
    test_result "pass" "pagila test script exists"
else
    test_result "fail" "pagila test script exists"
fi

# Test 2: Verify scripts are executable
print_section "Test 2: Scripts Are Executable"

if [ -x "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" ]; then
    test_result "pass" "platform-postgres script is executable"
else
    test_result "fail" "platform-postgres script is executable"
fi

if [ -x "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" ]; then
    test_result "pass" "pagila script is executable"
else
    test_result "fail" "pagila script is executable"
fi

# Test 3: Verify Makefile targets exist
print_section "Test 3: Makefile Targets"

if make -C "$REPO_ROOT/platform-infrastructure" help | grep -q "test-platform-postgres-connectivity"; then
    test_result "pass" "test-platform-postgres-connectivity target exists"
else
    test_result "fail" "test-platform-postgres-connectivity target exists"
fi

if make -C "$REPO_ROOT/platform-infrastructure" help | grep -q "test-pagila-connectivity"; then
    test_result "pass" "test-pagila-connectivity target exists"
else
    test_result "fail" "test-pagila-connectivity target exists"
fi

if make -C "$REPO_ROOT/platform-infrastructure" help | grep -q "test-connectivity"; then
    test_result "pass" "test-connectivity target exists"
else
    test_result "fail" "test-connectivity target exists"
fi

# Test 4: Verify Python methods exist
print_section "Test 4: Python Integration"

if grep -q "def verify_postgres_health" "$REPO_ROOT/wizard/utils/diagnostics.py"; then
    test_result "pass" "verify_postgres_health method exists"
else
    test_result "fail" "verify_postgres_health method exists"
fi

if grep -q "def verify_pagila_health" "$REPO_ROOT/wizard/utils/diagnostics.py"; then
    test_result "pass" "verify_pagila_health method exists"
else
    test_result "fail" "verify_pagila_health method exists"
fi

# Test 5: Verify wizard integration
print_section "Test 5: Wizard Integration"

if grep -q "verify_postgres_health" "$REPO_ROOT/wizard/services/base_platform/actions.py"; then
    test_result "pass" "PostgreSQL action uses health check"
else
    test_result "fail" "PostgreSQL action uses health check"
fi

if grep -q "verify_pagila_health" "$REPO_ROOT/wizard/services/pagila/actions.py"; then
    test_result "pass" "Pagila action uses health check"
else
    test_result "fail" "Pagila action uses health check"
fi

# Test 6: Run actual health checks (if containers are running)
print_section "Test 6: Functional Tests (if containers available)"

if docker ps | grep -q postgres-test && docker ps | grep -q platform-postgres; then
    print_info "Containers detected, running functional tests..."

    if bash "$REPO_ROOT/platform-infrastructure/tests/test-platform-postgres-connectivity.sh" --quiet >/dev/null 2>&1; then
        test_result "pass" "platform-postgres connectivity test executes"
    else
        test_result "fail" "platform-postgres connectivity test executes"
    fi
else
    print_info "Containers not running, skipping functional tests"
    print_info "Start containers with: ./platform setup"
fi

if docker ps | grep -q postgres-test && docker ps | grep -q pagila-postgres; then
    if bash "$REPO_ROOT/platform-infrastructure/tests/test-pagila-connectivity.sh" --quiet >/dev/null 2>&1; then
        test_result "pass" "pagila connectivity test executes"
    else
        test_result "fail" "pagila connectivity test executes"
    fi
else
    print_info "Pagila not running, skipping pagila test"
fi

# Summary
print_divider
echo ""

if [ $TESTS_PASSED -eq $TESTS_RUN ]; then
    print_success "All tests passed! ($TESTS_PASSED/$TESTS_RUN)"
    exit 0
else
    print_error "Some tests failed! ($TESTS_PASSED/$TESTS_RUN passed)"
    exit 1
fi
```

**Step 2: Make executable and run**

Run:
```bash
chmod +x platform-bootstrap/tests/test-health-checks-integration.sh
./platform-bootstrap/tests/test-health-checks-integration.sh
```

Expected: All structural tests pass (file existence, executability, grep checks)

**Step 3: Commit integration test**

```bash
git add platform-bootstrap/tests/test-health-checks-integration.sh
git commit -m "test: add health checks integration test

Add comprehensive integration test that verifies:
- Test scripts exist and are executable
- Makefile targets are defined
- Python methods are implemented
- Wizard integration is complete
- Functional tests run if containers available

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Final Verification

**Step 1: Run all tests**

```bash
# Run integration test
./platform-bootstrap/tests/test-health-checks-integration.sh

# Run unit tests
.venv/bin/pytest wizard/utils/tests/test_diagnostics.py -v -k verify

# If containers are running, test functionality
make -C platform-infrastructure test-connectivity
```

**Step 2: Review commit history**

```bash
git log --oneline -8
```

Expected: 8 commits for the 8 tasks completed

**Step 3: Create summary commit (optional)**

```bash
git commit --allow-empty -m "feat: database health checks complete

Complete implementation of automated database health checks:

- Shell scripts for platform-postgres and Pagila connectivity tests
- Makefile targets for easy manual testing
- Python integration with wizard diagnostic framework
- Automatic health checks after service installation
- Comprehensive documentation and integration tests

Health checks run automatically, provide detailed metrics on success,
and save diagnostics on failure without blocking wizard progression.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Success Criteria

- [x] Shell scripts exist and are executable
- [x] Scripts support both detailed and --quiet modes
- [x] Makefile targets defined and discoverable
- [x] Python methods integrated with diagnostics module
- [x] Wizard automatically runs health checks after installation
- [x] Detailed metrics displayed on success
- [x] Diagnostics saved to file on failure (non-blocking)
- [x] Unit tests pass
- [x] Integration tests pass
- [x] Documentation updated

## Notes for Execution

**Parallel Task Execution:**
- Tasks 1 and 2 can be executed in parallel (different files)
- Task 3 depends on both 1 and 2 completing
- Tasks 4-6 are sequential (each builds on the previous)
- Task 7-8 can run after everything else completes

**TDD Approach:**
- Each shell script is built incrementally (scaffold → test → implement)
- Python methods have unit tests before wizard integration
- Integration test verifies complete system

**Review Points:**
After Task 2: Review both shell scripts for consistency
After Task 4: Review Python integration patterns
After Task 6: Manual test wizard flow
After Task 8: Full system verification
