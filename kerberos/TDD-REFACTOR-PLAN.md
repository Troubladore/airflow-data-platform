# TDD Refactor Plan: Minimal Kerberos Sidecar

## Objective

Refactor the Kerberos sidecar from bloated (312 MB, 120+ packages) to minimal (50 MB, 15-20 packages) following strict TDD practices with maximum parallelism.

## Overview

Each task follows RED-GREEN-REFACTOR cycle:
- **RED**: Write failing test
- **GREEN**: Minimal code to pass
- **REFACTOR**: Clean up while staying green

Tasks are grouped to maximize parallel execution where dependencies allow.

---

## Phase 1: Test Infrastructure (Sequential - Foundation)

### Task 1.1: Create Minimal Sidecar Test Suite
**Can start**: Immediately
**Blocks**: All other tasks

**RED**:
- Write test: `test/minimal-sidecar.test.sh`
- Assert: Minimal image contains ONLY required packages
- Assert: Image size < 60 MB
- Assert: No build tools (gcc, g++, musl-dev)
- Assert: No ODBC/SQL tools (msodbcsql18, mssql-tools18)
- Assert: No Python packages
- Run test → **MUST FAIL** (current image has all these)

**GREEN**:
- Create `Dockerfile.minimal`
- Include ONLY: krb5, krb5-libs, bash, curl, ca-certificates
- Build image
- Run test → **MUST PASS**

**REFACTOR**:
- Optimize layer ordering
- Add build args for corporate registries

---

### Task 1.2: Create Image Size Test
**Can start**: Immediately
**Blocks**: Nothing (parallel with 1.1)

**RED**:
- Write test: `test/image-size.test.sh`
- Assert: `platform/kerberos-sidecar:minimal` < 60 MB
- Assert: Package count < 25
- Run test → **MUST FAIL** (no minimal image yet)

**GREEN**:
- Ensure Dockerfile.minimal builds image that passes
- Run test → **MUST PASS**

**REFACTOR**:
- Add detailed size breakdown reporting

---

### Task 1.3: Create Package Inventory Test
**Can start**: Immediately
**Blocks**: Nothing (parallel with 1.1, 1.2)

**RED**:
- Write test: `test/package-inventory.test.sh`
- Assert: Image contains krb5, krb5-libs, bash, curl, ca-certificates
- Assert: Image does NOT contain gcc, g++, python3, msodbcsql18, etc.
- Run test → **MUST FAIL**

**GREEN**:
- Ensure Dockerfile.minimal installs only required packages
- Run test → **MUST PASS**

**REFACTOR**:
- Generate package manifest for documentation

---

## Phase 2: Ticket Management Tests (After Phase 1 Complete)

### Task 2.1: Test Ticket Manager Script Works in Minimal Container
**Can start**: After 1.1 GREEN
**Blocks**: 3.1

**RED**:
- Write test: `test/ticket-manager-minimal.test.sh`
- Start minimal container with ticket manager script
- Assert: Script runs without errors
- Assert: No missing dependencies (bash, klist, etc.)
- Run test → **MUST FAIL** (script might need deps not in minimal image)

**GREEN**:
- Add missing runtime deps to Dockerfile.minimal (if any)
- Run test → **MUST PASS**

**REFACTOR**:
- Remove any unnecessary deps that snuck in

---

### Task 2.2: Test Health Check Works in Minimal Container
**Can start**: After 1.1 GREEN
**Blocks**: 3.2 (parallel with 2.1)

**RED**:
- Write test: `test/health-check-minimal.test.sh`
- Run minimal container with health check enabled
- Assert: Health check passes with valid ticket
- Assert: Health check fails without ticket
- Run test → **MUST FAIL** (health-check.sh might need deps)

**GREEN**:
- Ensure health-check.sh works in minimal environment
- Add deps if needed (should be none)
- Run test → **MUST PASS**

**REFACTOR**:
- Simplify health check if possible

---

### Task 2.3: Test Ticket Copying in Minimal Container
**Can start**: After 1.1 GREEN
**Blocks**: 3.3 (parallel with 2.1, 2.2)

**RED**:
- Write test: `test/ticket-copy-minimal.test.sh`
- Start minimal container with TICKET_MODE=copy
- Mount host ticket cache
- Assert: Tickets copied successfully
- Assert: klist shows valid principal
- Run test → **MUST FAIL** (might need additional deps)

**GREEN**:
- Ensure ticket copying works
- Add deps if needed
- Run test → **MUST PASS**

**REFACTOR**:
- Optimize ticket copy logic

---

## Phase 3: Integration Tests (After Phase 2 Complete)

### Task 3.1: Test End-to-End Ticket Management
**Can start**: After 2.1, 2.2, 2.3 GREEN
**Blocks**: Nothing

**RED**:
- Write test: `test/e2e-minimal-sidecar.test.sh`
- Start minimal sidecar with real ERUDITIS.LAB tickets
- Assert: Sidecar healthy
- Assert: Tickets refreshed every COPY_INTERVAL
- Assert: Shared volume has valid tickets
- Run test → **MUST FAIL** (integration not proven yet)

**GREEN**:
- Run actual minimal sidecar with real config
- Verify all assertions pass
- Run test → **MUST PASS**

**REFACTOR**:
- Add logging for easier debugging

---

### Task 3.2: Test Minimal Sidecar with PostgreSQL
**Can start**: After 2.1, 2.2, 2.3 GREEN
**Blocks**: Nothing (parallel with 3.1)

**RED**:
- Write test: `test/postgres-gssapi-minimal.test.sh`
- Start minimal sidecar
- Run psql client container mounting ticket cache
- Assert: GSSAPI connection succeeds to sqlpg.eruditis.lab
- Run test → **MUST FAIL** (postgres client container doesn't exist yet)

**GREEN**:
- Create postgres test container (separate from sidecar)
- Mount ticket cache from minimal sidecar
- Run test → **MUST PASS**

**REFACTOR**:
- Document postgres test container usage

---

### Task 3.3: Test Minimal Sidecar with SQL Server Test Container
**Can start**: After 2.1, 2.2, 2.3 GREEN
**Blocks**: Nothing (parallel with 3.1, 3.2)

**RED**:
- Write test: `test/sqlserver-test-container.test.sh`
- Build platform/sqlcmd-test (already has Dockerfile.sqlcmd-test)
- Start minimal sidecar
- Run sqlcmd-test container mounting ticket cache
- Assert: sqlcmd available
- Assert: Can connect to SQL Server (when available)
- Run test → **MUST FAIL** (sqlcmd-test not built)

**GREEN**:
- Build sqlcmd-test image
- Mount ticket cache from minimal sidecar
- Run test → **MUST PASS**

**REFACTOR**:
- Add ACCEPT_EULA=Y to Dockerfile.sqlcmd-test

---

## Phase 4: Migration & Documentation (After Phase 3 Complete)

### Task 4.1: Create Migration Guide
**Can start**: After all Phase 3 GREEN
**Blocks**: Nothing

**RED**:
- Write test: `test/migration-guide.test.sh`
- Assert: Migration guide exists
- Assert: Contains legacy → minimal migration steps
- Assert: Documents test container usage
- Run test → **MUST FAIL** (no guide yet)

**GREEN**:
- Create MIGRATION-GUIDE.md
- Include step-by-step instructions
- Run test → **MUST PASS**

**REFACTOR**:
- Add troubleshooting section

---

### Task 4.2: Update Main README
**Can start**: After 4.1 GREEN
**Blocks**: Nothing (parallel with 4.3)

**RED**:
- Write test: `test/readme-accuracy.test.sh`
- Assert: README references Dockerfile.minimal
- Assert: README shows minimal sidecar usage
- Assert: README links to test containers
- Run test → **MUST FAIL**

**GREEN**:
- Update kerberos/kerberos-sidecar/README.md
- Document minimal vs legacy
- Run test → **MUST PASS**

**REFACTOR**:
- Add diagrams showing separation of concerns

---

### Task 4.3: Rename Dockerfiles
**Can start**: After 4.1 GREEN
**Blocks**: Nothing (parallel with 4.2)

**RED**:
- Write test: `test/dockerfile-names.test.sh`
- Assert: Dockerfile.legacy exists (current bloated one)
- Assert: Dockerfile exists (minimal one)
- Assert: Makefile builds both
- Run test → **MUST FAIL**

**GREEN**:
- Rename: Dockerfile → Dockerfile.legacy
- Rename: Dockerfile.minimal → Dockerfile
- Update Makefile
- Run test → **MUST PASS**

**REFACTOR**:
- Add comments explaining when to use each

---

## Phase 5: Corporate Alignment (After Phase 4 Complete)

### Task 5.1: Add Chainguard Base Support
**Can start**: After Phase 4 GREEN
**Blocks**: Nothing

**RED**:
- Write test: `test/chainguard-base.test.sh`
- Assert: Dockerfile accepts IMAGE_ALPINE build arg
- Assert: Can build with chainguard/wolfi-base
- Assert: Image still < 60 MB
- Run test → **MUST FAIL** (not implemented)

**GREEN**:
- Update Dockerfile to support IMAGE_ALPINE
- Test with Chainguard base
- Run test → **MUST PASS**

**REFACTOR**:
- Document corporate registry usage

---

### Task 5.2: Add ACCEPT_EULA to Test Containers
**Can start**: After Phase 4 GREEN
**Blocks**: Nothing (parallel with 5.1)

**RED**:
- Write test: `test/eula-acceptance.test.sh`
- Assert: Dockerfile.sqlcmd-test has ACCEPT_EULA=Y
- Assert: Dockerfile.test-image has ACCEPT_EULA=Y
- Run test → **MUST FAIL**

**GREEN**:
- Add ENV ACCEPT_EULA=Y to test container Dockerfiles
- Run test → **MUST PASS**

**REFACTOR**:
- Add comments explaining EULA requirement

---

## Parallelization Map

```
Phase 1 (All Parallel):
├── Task 1.1: Minimal Sidecar Test Suite
├── Task 1.2: Image Size Test
└── Task 1.3: Package Inventory Test

Phase 2 (All Parallel, after Phase 1):
├── Task 2.1: Ticket Manager Test
├── Task 2.2: Health Check Test
└── Task 2.3: Ticket Copying Test

Phase 3 (All Parallel, after Phase 2):
├── Task 3.1: E2E Test
├── Task 3.2: PostgreSQL Test
└── Task 3.3: SQL Server Test

Phase 4 (Sequential start, then parallel):
├── Task 4.1: Migration Guide (sequential)
└── After 4.1:
    ├── Task 4.2: Update README
    └── Task 4.3: Rename Dockerfiles

Phase 5 (All Parallel, after Phase 4):
├── Task 5.1: Chainguard Base
└── Task 5.2: ACCEPT_EULA
```

## Success Criteria

All tests GREEN:
- ✅ Minimal sidecar image < 60 MB
- ✅ Package count < 25
- ✅ No build tools in production image
- ✅ No ODBC/SQL tools in sidecar
- ✅ Ticket management works in minimal container
- ✅ PostgreSQL GSSAPI works with minimal sidecar
- ✅ SQL Server test container works independently
- ✅ Documentation complete and accurate
- ✅ Corporate registry support (Chainguard base)
- ✅ EULA acceptance in test containers

## Test Execution Strategy

1. **Phase 1**: 3 parallel test writers
2. **Phase 2**: 3 parallel test writers (after Phase 1 GREEN)
3. **Phase 3**: 3 parallel test writers (after Phase 2 GREEN)
4. **Phase 4**: Sequential guide, then 2 parallel docs
5. **Phase 5**: 2 parallel corporate features

**Total tasks**: 14
**Maximum parallelism**: 3 concurrent tasks per phase
**Estimated time**: 4-6 hours (with parallelization vs 12+ sequential)
