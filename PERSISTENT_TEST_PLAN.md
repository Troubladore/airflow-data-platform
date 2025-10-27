# Persistent Test Plan - Wizard End-to-End Validation

**Purpose:** Document all test paths so they can be re-run without reinvention
**Location:** Run from repo root: `~/repos/airflow-data-platform`

## Quick Test Commands

```bash
# Basic smoke test (30 sec)
./QUICK_SMOKE_TEST.sh

# Full validation (10 min)
uv run python COMPREHENSIVE_VALIDATION.py

# Specific service test
./test_postgres_only.sh
./test_kerberos_only.sh
./test_pagila_only.sh

# Full cycle (setup + verify + teardown)
./FULL_CYCLE_TEST.sh
```

## Test Matrix - All Scenarios

### Category 1: Single Service (Fast - 30 sec each)

**Test 1.1: Postgres Only - Passwordless**
```bash
Inputs: n,n,n, ,n,n,5432
Verify: platform-postgres container, trust auth, port 5432
```

**Test 1.2: Postgres Only - With Password**
```bash
Inputs: n,n,n, ,n,y,testpass,5432
Verify: platform-postgres container, md5 auth, can't connect without password
```

**Test 1.3: Postgres Only - Custom Port**
```bash
Inputs: n,n,n, ,n,n,5433
Verify: platform-postgres container, port 5433 internally
```

**Test 1.4: Postgres Only - Custom Image**
```bash
Inputs: n,n,n,postgres:16,n,n,5432
Verify: postgres:16 image pulled, container uses postgres:16
```

### Category 2: Two Services (Medium - 60 sec each)

**Test 2.1: Postgres + Kerberos**
```bash
Inputs: n,y,n, ,n,n,5432,EXAMPLE.COM,ubuntu:22.04
Verify: platform-postgres + kerberos-sidecar-mock containers
```

**Test 2.2: Postgres + Pagila**
```bash
Inputs: n,n,y, ,n,n,5432,
Verify: platform-postgres container, pagila repo cloned, pagila DB exists
```

### Category 3: Multi-Service (Slow - 120 sec each)

**Test 3.1: All Services (No OpenMetadata)**
```bash
Inputs: n,y,y, ,n,n,5432,EXAMPLE.COM,ubuntu:22.04,
Verify: postgres + kerberos + pagila all working
```

### Category 4: Error Paths (Fast - 15 sec each)

**Test 4.1: Invalid Image**
```bash
Inputs: n,n,n,invalid!image,postgres:17.5-alpine,n,n,5432
Verify: Shows error, re-prompts, accepts valid input, completes
```

**Test 4.2: Invalid Port**
```bash
Inputs: n,n,n, ,n,n,999999,5432
Verify: Shows "Port must be between 1024-65535", re-prompts, accepts 5432
```

**Test 4.3: Docker Stopped**
```bash
Steps: Stop Docker daemon, run setup
Verify: Graceful error message, suggests starting Docker
```

### Category 5: Teardown (Medium - 45 sec each)

**Test 5.1: Clean-Slate Removes All**
```bash
Setup: Postgres only
Clean-slate inputs: y,n,n,y,y,y,y
Verify: Container removed, volume removed, images kept
```

**Test 5.2: Clean-Slate Selective**
```bash
Setup: Postgres + Kerberos
Clean-slate: Remove Kerberos only
Verify: Kerberos gone, Postgres still running
```

## Test Automation Scripts (Persistent)

### QUICK_SMOKE_TEST.sh
```bash
#!/bin/bash
# 30-second smoke test - verifies basic functionality

./platform setup << EOF
n
n
n

n
n
5432
EOF

docker ps | grep platform-postgres || exit 1
echo "✓ Smoke test PASS"
```

### COMPREHENSIVE_VALIDATION.py
```python
#!/usr/bin/env python3
"""All scenarios from test matrix."""

scenarios = [
    # Category 1: Single service (4 tests)
    {'name': '1.1 Postgres passwordless', 'inputs': ...},
    {'name': '1.2 Postgres with password', 'inputs': ...},
    # ... all 15 scenarios
]

for scenario in scenarios:
    run_test(scenario)

print(f"{passed}/{total} scenarios pass")
```

### Individual Service Tests

**test_postgres_only.sh** - Just postgres, all paths
**test_kerberos_only.sh** - Just kerberos, domain vs non-domain
**test_pagila_only.sh** - Just pagila, verify DB created

---

## Test Results Template (Update After Each Run)

```
Last Run: 2025-10-27 01:30
Branch: feature/wizard-ux-polish

Category 1 (Single Service): 3/4 PASS
  ✓ 1.1 Passwordless
  ✓ 1.2 With password
  ✗ 1.3 Custom port (not tested yet)
  ✗ 1.4 Custom image (image pull fails)

Category 2 (Two Services): 2/2 PASS
  ✓ 2.1 Postgres + Kerberos
  ✓ 2.2 Postgres + Pagila

Category 3 (Multi-Service): 0/1 tested
  ? 3.1 All services

Category 4 (Error Paths): 2/3 PASS
  ✓ 4.1 Invalid image
  ✓ 4.2 Invalid port
  ? 4.3 Docker stopped

Category 5 (Teardown): 1/2 PASS
  ✓ 5.1 Remove all
  ? 5.2 Selective removal

TOTAL: 8/15 scenarios validated (53%)
```

---

## Known Issues Log (Persistent)

**Issue #1: Database init fails but wizard continues**
- Status: OPEN
- Severity: CRITICAL
- Found: 2025-10-27 00:45
- Fix: Add error handling

**Issue #2: Custom images not pulled**
- Status: FIXED (commit 0843ec1)
- Severity: HIGH
- Found: 2025-10-27 00:50
- Fix: Added pull_image action

**Issue #3: Kerberos container not created**
- Status: FIXED (commit 7c5a514)
- Severity: HIGH
- Found: 2025-10-27 01:15
- Fix: Added mock container creation

**Issue #4: No progress feedback during actions**
- Status: FIXED (commit 59403ec)
- Severity: MEDIUM
- Found: 2025-10-27 01:20
- Fix: Added display messages to all actions

---

This document persists all test scenarios, scripts, and results.
Update TEST_RESULTS_TEMPLATE after each test run.
