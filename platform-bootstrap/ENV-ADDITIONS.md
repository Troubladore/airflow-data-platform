# Environment Variable Additions for Test Container Configuration

## Purpose
This document specifies the environment variables that need to be added to `platform-bootstrap/.env.example` to support the new test container configuration feature (Phase 2).

## Current State
The `.env.example` file currently includes:
- Platform service configuration (Kerberos, OpenMetadata)
- Corporate image sources for Layer 1 build
- PostgreSQL configuration
- Microsoft ODBC/SQL Tools sources
- Pagila test database configuration

**MISSING**: Configuration for test containers (postgres-test and sqlcmd-test)

## Required Environment Variables

The following variables need to be added to `.env.example`:

1. **IMAGE_POSTGRES_TEST** - Base image for building postgres-test container
2. **POSTGRES_TEST_PREBUILT** - Boolean flag indicating if postgres-test image is prebuilt
3. **IMAGE_SQLCMD_TEST** - Base image for building sqlcmd-test container
4. **SQLCMD_TEST_PREBUILT** - Boolean flag indicating if sqlcmd-test image is prebuilt

## Documentation Comments

The section should include comprehensive documentation similar to existing sections:

### Section Header
```bash
# ==========================================
# Test Containers (Base Platform)
# ==========================================
```

### Explanatory Comment
```bash
# Test containers provide Kerberos-enabled database clients for testing
# authenticated connections to SQL Server and PostgreSQL.
#
# postgres-test: PostgreSQL client (psql) with Kerberos/GSSAPI support
# sqlcmd-test:   SQL Server client (sqlcmd) with Kerberos/GSSAPI support
#
# Both containers include:
#   - Kerberos client libraries (krb5)
#   - GSSAPI authentication support
#   - unixODBC for database connectivity
#   - Non-root user (testuser, uid 10001)
#
# Build Modes:
#   PREBUILT=false (default): Build from base image, add dependencies
#   PREBUILT=true:            Use image as-is (all deps pre-installed)
#
# Default: Uses alpine:latest and builds at runtime
# Corporate: Use your organization's approved base images
```

### Variable Definitions with Inline Comments
```bash
# PostgreSQL Test Container
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false

# SQL Server Test Container
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false
```

## Example Corporate Configurations

### Scenario 1: Standard Alpine Base (Default)
```bash
# Use public alpine:latest, build dependencies at runtime
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false
```

### Scenario 2: Corporate Artifactory Mirror
```bash
# Mirror of alpine:latest from corporate Artifactory, build at runtime
IMAGE_POSTGRES_TEST=artifactory.company.com/docker-remote/library/alpine:latest
POSTGRES_TEST_PREBUILT=false
IMAGE_SQLCMD_TEST=artifactory.company.com/docker-remote/library/alpine:latest
SQLCMD_TEST_PREBUILT=false
```

### Scenario 3: Fully Prebuilt Corporate Images
```bash
# Corporate images with all dependencies pre-installed
IMAGE_POSTGRES_TEST=artifactory.company.com/docker-local/platform/postgres-test:2025.1
POSTGRES_TEST_PREBUILT=true
IMAGE_SQLCMD_TEST=artifactory.company.com/docker-local/platform/sqlcmd-test:2025.1
SQLCMD_TEST_PREBUILT=true

# Note: Prebuilt images must include:
#   - krb5 client libraries
#   - psql or sqlcmd client
#   - unixODBC and GSSAPI support
#   - testuser (uid 10001)
```

### Scenario 4: Mixed Mode (One Prebuilt, One Build)
```bash
# Corporate postgres-test prebuilt, standard sqlcmd-test built at runtime
IMAGE_POSTGRES_TEST=registry.corp.net/approved/postgres-client:stable
POSTGRES_TEST_PREBUILT=true
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false
```

### Scenario 5: Different Base Images
```bash
# Use different base images for different test containers
IMAGE_POSTGRES_TEST=alpine:3.19
POSTGRES_TEST_PREBUILT=false
IMAGE_SQLCMD_TEST=ubuntu:22.04
SQLCMD_TEST_PREBUILT=false

# Note: Dockerfiles support any base image with apk/apt package managers
```

## Recommended Placement in .env.example

Add this section **after** the "Shared PostgreSQL Image" section (line 196) and **before** the "PostgreSQL Authentication Mode" section (line 198).

This placement logically groups test containers with the core PostgreSQL configuration while keeping authentication settings separate.

## References

- **Design Document**: `docs/design/base-platform-refactor.md` - Section "Test Container Configuration"
- **Implementation Plan**: `docs/plans/2025-11-01-phase2-test-container-config-TDD.md` - Task 6
- **Dockerfiles**:
  - `platform-infrastructure/test-containers/postgres-test/Dockerfile`
  - `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`
- **Makefile Targets**: `build-postgres-test`, `build-sqlcmd-test` in root Makefile

## Task Context

This document is part of **Task 6a (RED phase)** of the Phase 2 TDD implementation plan.

**Task**: Verify that test container configuration is missing from `.env.example` and document what needs to be added.

**Next Step**: Task 6b (GREEN phase) will implement these additions in the actual `.env.example` file.
