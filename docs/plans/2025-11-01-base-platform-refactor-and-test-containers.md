# Base Platform Refactor and Test Container Configuration

**Date:** 2025-11-01
**Status:** Design Approved
**Implementation:** Two-phase approach

## Overview

This design addresses two related improvements:

1. **Phase 1:** Refactor `services.postgres` → `services.base_platform` to correctly represent PostgreSQL as base platform infrastructure (not a standalone service)
2. **Phase 2:** Add test container configuration to wizard for PostgreSQL and SQL Server connectivity testing in corporate/restricted network environments

## Problem Statement

### Current State

**Misnomer:** PostgreSQL is configured as `services.postgres`, but it's actually part of the base platform infrastructure that supports multiple services (OpenMetadata, Airflow metastore, future platform databases).

**Gap:** The platform includes lightweight test containers for connectivity validation:
- `Dockerfile.postgres-test` - PostgreSQL client + Kerberos for testing PostgreSQL GSSAPI auth
- `Dockerfile.sqlcmd-test` - SQL Server client + Kerberos for testing MSSQL Kerberos auth

These test containers are built manually and not configurable through the wizard. In restricted corporate networks, users may need to:
- Use approved base images (e.g., Chainguard Wolfi)
- Reference internal package mirrors
- Use prebuilt images from corporate registries

Currently, there's no way to configure this through the wizard.

## Architecture Context

The platform has two distinct architectural layers that must be clearly separated:

### Configuration Layer (Wizard)
**Location**: `wizard/services/base_platform/`
**Purpose**: User-facing prompts, validation, state management
**Outputs**: `platform-config.yaml`, `platform-bootstrap/.env`
**Responsibility**: Captures what the user wants configured

### Runtime/Operational Layer
**Location**: `platform-infrastructure/`
**Purpose**: Actual running services, Dockerfiles, compose files, build artifacts
**Inputs**: Configuration from `platform-bootstrap/.env`
**Responsibility**: Implements how services actually run

This separation ensures configuration (what user wants) stays separate from implementation (how services run). Test containers are runtime artifacts, so they belong in `platform-infrastructure/`, not `kerberos/` (which would imply Kerberos ownership).

## Design Goals

1. Correct the architectural naming (postgres → base_platform)
2. Enable wizard configuration of test container images
3. Move test containers to proper location (`platform-infrastructure/test-containers/`)
4. Follow established Kerberos pattern (IMAGE + PREBUILT boolean, not 3 separate properties)
5. Support both "build from base" and "use prebuilt" workflows
6. Simplify corporate usage (prebuilt images instead of corporate mirror complexity)
7. Maintain clean migration path (no permanent backward compatibility)
8. Store configuration persistently across wizard sessions

## Phase 1: Refactor to `services.base_platform`

### Rationale

PostgreSQL is not a standalone service the user "installs" - it's foundational infrastructure that the platform requires. Future base platform components might include message queues, caching layers, etc. The configuration namespace should reflect this architecture.

### Changes

#### 1. Directory Structure

```
wizard/services/postgres/          → wizard/services/base_platform/
  ├── spec.yaml                     → spec.yaml
  ├── actions.py                    → actions.py
  ├── validators.py                 → validators.py
  ├── discovery.py                  → discovery.py
  ├── teardown_actions.py           → teardown_actions.py
  ├── teardown-spec.yaml            → teardown-spec.yaml
  └── tests/                        → tests/
```

#### 2. State Key Migration

```yaml
# Old keys → New keys
services.postgres.enabled           → services.base_platform.postgres.enabled
services.postgres.image             → services.base_platform.postgres.image
services.postgres.port              → services.base_platform.postgres.port
services.postgres.user              → services.base_platform.postgres.user
services.postgres.password          → services.base_platform.postgres.password
services.postgres.passwordless      → services.base_platform.postgres.passwordless
```

#### 3. Migration Logic

**Location:** `wizard/services/base_platform/actions.py` - new action `migrate_legacy_postgres_config()`

**Behavior:**
1. Run automatically as first step in base_platform spec
2. Check if `platform-config.yaml` contains any `services.postgres` keys
3. If found:
   - Read all `services.postgres.*` values
   - Write to `services.base_platform.postgres.*`
   - **Delete all `services.postgres.*` keys**
   - Save updated config
4. Idempotent (safe to run multiple times)
5. Display message if migration occurred

**No Backward Compatibility:** After migration runs, all code uses only `services.base_platform.postgres.*`. No fallback checks.

#### 4. Code Updates

**Files requiring updates:**
- `wizard/services/base_platform/spec.yaml` - Update service name
- `wizard/services/base_platform/actions.py` - Use new state keys
- `wizard/services/base_platform/validators.py` - Use new state keys
- `wizard/services/base_platform/discovery.py` - Use new state keys
- `wizard/services/base_platform/teardown_actions.py` - Use new state keys
- `wizard/services/__init__.py` - Update service registration
- `wizard/flows/setup.yaml` - Reference base_platform service
- `wizard/flows/clean-slate.yaml` - Reference base_platform service
- All test files referencing postgres service
- All imports: ~~`from wizard.services.postgres`~~ → `from wizard.services.base_platform` ✅ COMPLETED

#### 5. Spec File Changes

**`wizard/services/base_platform/spec.yaml`:**
```yaml
service: base_platform  # Changed from: postgres
version: "1.0"
description: "Base platform infrastructure (PostgreSQL, test containers)"

steps:
  - id: migrate_legacy_config
    type: action
    action: base_platform.migrate_legacy_postgres_config
    next: postgres_image_input

  - id: postgres_image_input
    # ... existing postgres setup steps
    # All state_key values use services.base_platform.postgres.*
```

### Testing Strategy

1. Create test with old `services.postgres` config
2. Run wizard, verify migration occurs
3. Verify old keys are deleted
4. Verify new keys work correctly
5. Run migration again, verify idempotent
6. Test clean-slate with new structure
7. Test all existing postgres functionality

### Rollout

1. Implement migration logic
2. Update all code to use new keys
3. Update all tests
4. Verify in development
5. Merge to main
6. Migration runs automatically for existing users on next wizard invocation

## Phase 2: Test Container Configuration

### Rationale

Test containers are lightweight, ephemeral runners used for connectivity validation. In corporate environments:
- Users may only have access to approved base images (e.g., Chainguard, internal Alpine mirrors)
- Users may have prebuilt images with all tools already installed
- Package repositories may be internal mirrors requiring special URLs

The wizard should support configuring these containers so they work in restricted networks.

### Architecture

Test containers are **build-time artifacts**, not runtime services:
- Built once from configured base image
- Invoked on-demand via `docker run --rm`
- Used by Kerberos progressive tests
- Used by manual connectivity testing scripts
- **NOT** started/stopped like persistent services

### Components

#### 1. Refactored Dockerfile Templates

**Location Change**: Move test container Dockerfiles from `kerberos/kerberos-sidecar/` to `platform-infrastructure/test-containers/` to reflect proper ownership (these are base platform infrastructure, not Kerberos-specific).

**`platform-infrastructure/test-containers/postgres-test/Dockerfile`:**
```dockerfile
# Minimal PostgreSQL + Kerberos Test Container
# ==============================================
# Template for corporate environments with restricted base images
# Customize BASE_IMAGE to match your approved registry

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install PostgreSQL client with GSSAPI + Kerberos tools + ODBC
# Adjust package names for your base (Alpine shown)
RUN apk update && apk add --no-cache \
    postgresql17-client \
    krb5 krb5-libs krb5-conf \
    unixodbc unixodbc-dev \
    ca-certificates tzdata

# Create non-root user
RUN adduser -D -u 10001 testuser
USER testuser

# Setup directories for psql and Kerberos config
RUN mkdir -p /home/testuser/.postgresql && \
    chmod 700 /home/testuser/.postgresql

ENTRYPOINT ["/bin/sh", "-lc"]
CMD ["psql --version"]
```

**Key features:**
- Parameterized `BASE_IMAGE` for corporate registry flexibility
- Uses latest package versions from Alpine repos (not pinned)
- Includes unixODBC for ODBC-based PostgreSQL connections
- Non-root user for security
- Minimal layer count
- ~50MB compressed (vs ~230MB for postgres:16-alpine)

**`platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`:**
```dockerfile
# Minimal SQL Server + Kerberos Test Container
# ==============================================
# For corporate environments that cannot access Microsoft downloads,
# use prebuilt images instead of building from base.

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

ENV ACCEPT_EULA=Y

# Install Kerberos, ODBC infrastructure, and FreeTDS
RUN apk update && apk add --no-cache \
    krb5 krb5-libs krb5-conf \
    ca-certificates tzdata \
    curl \
    unixodbc unixodbc-dev \
    freetds freetds-dev

# Install Microsoft SQL Server tools from public source
# Corporate environments: Use prebuilt images if download.microsoft.com is blocked
RUN arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    base_url="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8" && \
    cd /tmp && \
    curl -fsSL -o msodbc.apk "${base_url}/msodbcsql18_18.4.1.1-1_${arch}.apk" && \
    curl -fsSL -o mssql-tools.apk "${base_url}/mssql-tools18_18.4.1.1-1_${arch}.apk" && \
    apk add --allow-untrusted msodbc.apk mssql-tools.apk && \
    rm -f *.apk

ENV PATH="/opt/mssql-tools18/bin:${PATH}"

# Create non-root user
RUN adduser -D -u 10001 testuser
USER testuser

ENTRYPOINT ["/bin/sh", "-lc"]
CMD ["sqlcmd -? && odbcinst -q -d"]
```

**Key features:**
- Includes **FreeTDS** (alternative SQL Server driver)
- Includes **unixODBC** for DSN configuration (`/etc/odbc.ini`)
- Includes **odbcinst** for driver inspection
- Downloads Microsoft tools from public source (no corporate mirror support)
- Microsoft EULA acceptance documented
- Non-root user

**Why FreeTDS + unixODBC:**
- FreeTDS provides fallback if Microsoft driver has issues
- unixODBC enables DSN-based connections for cleaner connection strings
- `odbcinst -q -d` helps troubleshoot driver registration issues

**Corporate Environments:**
- If download.microsoft.com is blocked, prebuild this image and use prebuilt mode
- Attempting to support corporate mirrors adds too much complexity (auth tokens, etc.)

#### 2. Wizard Sub-Spec

**`wizard/services/base_platform/test-containers-spec.yaml`:**

Following the established Kerberos pattern (IMAGE + PREBUILT boolean):

```yaml
# Test container configuration for base platform
# Invoked from main base_platform/spec.yaml

steps:
  - id: postgres_test_prebuilt
    type: boolean
    state_key: services.base_platform.test_containers.postgres_test.prebuilt
    default_from: services.base_platform.test_containers.postgres_test.prebuilt
    prompt: "Use prebuilt PostgreSQL test image (vs. building from base)?"
    default_value: false
    next: postgres_test_image

  - id: postgres_test_image
    type: string
    state_key: services.base_platform.test_containers.postgres_test.image
    default_from: services.base_platform.test_containers.postgres_test.image
    prompt: "PostgreSQL test container image (base to build from, or prebuilt image path):"
    default_value: "alpine:latest"
    next: sqlcmd_test_prebuilt

  - id: sqlcmd_test_prebuilt
    type: boolean
    state_key: services.base_platform.test_containers.sqlcmd_test.prebuilt
    default_from: services.base_platform.test_containers.sqlcmd_test.prebuilt
    prompt: "Use prebuilt SQL Server test image (vs. building from base)?"
    default_value: false
    next: sqlcmd_test_image

  - id: sqlcmd_test_image
    type: string
    state_key: services.base_platform.test_containers.sqlcmd_test.image
    default_from: services.base_platform.test_containers.sqlcmd_test.image
    prompt: "SQL Server test container image (base to build from, or prebuilt image path):"
    default_value: "alpine:latest"
    next: save_test_config

  - id: save_test_config
    type: action
    action: base_platform.save_test_container_config
    next: finish
```

**Flow Logic (Simplified):**
1. Ask if using prebuilt PostgreSQL test image
2. Prompt for image (interpretation depends on prebuilt flag)
3. Ask if using prebuilt SQL Server test image
4. Prompt for image (interpretation depends on prebuilt flag)
5. Save configuration

**Image Interpretation:**
- If `prebuilt=false`: Image is base to build from (e.g., `alpine:latest`, `cgr.dev/chainguard/wolfi-base`)
- If `prebuilt=true`: Image is complete prebuilt path (e.g., `mycorp.io/postgres-test:v1`)

#### 3. Integration into Main Spec

**`wizard/services/base_platform/spec.yaml`:**
```yaml
steps:
  # ... existing postgres setup steps ...

  - id: configure_test_containers
    type: action
    action: base_platform.invoke_test_container_spec
    next: finish
```

The action `invoke_test_container_spec` loads and executes `test-containers-spec.yaml`.

#### 4. Configuration Storage

Following Kerberos pattern (IMAGE + PREBUILT boolean):

**`platform-config.yaml`:**
```yaml
services:
  base_platform:
    postgres:
      enabled: true
      image: postgres:17.5-alpine
      port: 5432
      user: platform_admin
      password: changeme
      passwordless: false

    test_containers:
      postgres_test:
        image: "alpine:latest"
        prebuilt: false
        # For prebuilt:
        # image: "mycorp.jfrog.io/test-images/postgres-test:v1"
        # prebuilt: true

      sqlcmd_test:
        image: "alpine:latest"
        prebuilt: false
        # For prebuilt:
        # image: "mycorp.jfrog.io/test-images/sqlcmd-test:v1"
        # prebuilt: true
```

**`platform-bootstrap/.env`:**
```bash
# PostgreSQL (base platform)
IMAGE_POSTGRES=postgres:17.5-alpine
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=changeme

# Test containers (follows Kerberos pattern)
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false

IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false

# Example corporate configuration:
# IMAGE_POSTGRES_TEST=mycorp.jfrog.io/approved/alpine:3.22
# POSTGRES_TEST_PREBUILT=false  # Build from corporate base
#
# IMAGE_SQLCMD_TEST=mycorp.jfrog.io/test-images/sqlcmd-test:v1
# SQLCMD_TEST_PREBUILT=true  # Use prebuilt corporate image
```

#### 5. Build Integration

**Location**: Root `Makefile` (test containers are base platform infrastructure, build targets belong at root level)

**Makefile targets** (handles both build and prebuilt modes):
```makefile
build-postgres-test:
	@source platform-bootstrap/.env 2>/dev/null || true && \
	if [ "$${POSTGRES_TEST_PREBUILT}" = "true" ]; then \
		echo "Using prebuilt image: $${IMAGE_POSTGRES_TEST}"; \
		docker pull $${IMAGE_POSTGRES_TEST} && \
		docker tag $${IMAGE_POSTGRES_TEST} platform/postgres-test:latest; \
	else \
		echo "Building postgres-test from base: $${IMAGE_POSTGRES_TEST:-alpine:latest}"; \
		docker build \
		  -f platform-infrastructure/test-containers/postgres-test/Dockerfile \
		  --build-arg BASE_IMAGE=$${IMAGE_POSTGRES_TEST:-alpine:latest} \
		  -t platform/postgres-test:latest \
		  platform-infrastructure/test-containers/postgres-test/; \
	fi

build-sqlcmd-test:
	@source platform-bootstrap/.env 2>/dev/null || true && \
	if [ "$${SQLCMD_TEST_PREBUILT}" = "true" ]; then \
		echo "Using prebuilt image: $${IMAGE_SQLCMD_TEST}"; \
		docker pull $${IMAGE_SQLCMD_TEST} && \
		docker tag $${IMAGE_SQLCMD_TEST} platform/sqlcmd-test:latest; \
	else \
		echo "Building sqlcmd-test from base: $${IMAGE_SQLCMD_TEST:-alpine:latest}"; \
		docker build \
		  -f platform-infrastructure/test-containers/sqlcmd-test/Dockerfile \
		  --build-arg BASE_IMAGE=$${IMAGE_SQLCMD_TEST:-alpine:latest} \
		  -t platform/sqlcmd-test:latest \
		  platform-infrastructure/test-containers/sqlcmd-test/; \
	fi
```

**Build Logic:**
- If `PREBUILT=true`: Pull configured image and tag as `platform/*:latest`
- If `PREBUILT=false`: Build from configured base image using Dockerfile

### Usage Scenarios

#### Scenario 1: Corporate Network - Build from Approved Base

User workflow:
1. Run `./platform setup`
2. Configure base platform (postgres)
3. Prompted for test containers:
   - Build from base? **Yes**
   - Base image: `mycorp.jfrog.io/chainguard/wolfi-base:latest`
4. Configuration saved
5. User runs: `make build-postgres-test build-sqlcmd-test`
6. Test containers built from corporate base image
7. Progressive tests use custom-built containers

#### Scenario 2: Corporate Network - Prebuilt Images

User workflow:
1. Corporate DevOps team builds test images centrally
2. Publishes to: `mycorp.io/test-images/postgres-kerb-test:v1.2`
3. User runs `./platform setup`
4. Prompted for test containers:
   - Build from base? **No**
   - Prebuilt image: `mycorp.io/test-images/postgres-kerb-test:v1.2`
5. Configuration saved
6. No build needed - tests use prebuilt image directly

#### Scenario 3: Open Internet - Default Images

User workflow:
1. Run `./platform setup`
2. Accept defaults for test containers (alpine:latest)
3. Run `make build-postgres-test build-sqlcmd-test`
4. Works out of the box

### Testing Strategy

1. **Unit tests**: Test container spec loading and validation
2. **Integration tests**:
   - Test build from alpine:latest
   - Test build from custom base
   - Verify environment variable propagation
3. **Acceptance tests**:
   - Run progressive tests with default images
   - Run progressive tests with custom base images
   - Verify DSN configuration works (sqlcmd)
   - Verify FreeTDS fallback works

### Migration Impact

Phase 2 is additive - no migration needed:
- New users get test container prompts automatically
- Existing users see prompts on next setup run
- Defaults work without configuration

## Implementation Sequence

### Phase 1: Base Platform Refactor

1. Create feature branch: `refactor/base-platform`
2. Implement migration action
3. Rename directory and update imports
4. Update all state keys in code
5. Update specs and flows
6. Update tests
7. Verify migration with old config
8. Merge to main

**Estimated effort:** 4-6 hours

### Phase 2: Test Container Configuration

1. Create feature branch: `feature/test-container-config`
2. Move Dockerfiles: `kerberos/kerberos-sidecar/Dockerfile.{postgres,sqlcmd}-test` → `platform-infrastructure/test-containers/{postgres-test,sqlcmd-test}/Dockerfile`
3. Refactor Dockerfiles: Add BASE_IMAGE build arg, add unixODBC to postgres-test, remove MSSQL_TOOLS_URL from sqlcmd-test, add non-root users
4. Create test-containers-spec.yaml (following Kerberos IMAGE + PREBUILT pattern)
5. Implement wizard actions: `invoke_test_container_spec` and `save_test_container_config`
6. Update main spec to invoke sub-spec after postgres setup
7. Add Makefile targets to root Makefile: `build-postgres-test` and `build-sqlcmd-test` (with prebuilt mode support)
8. Update platform-bootstrap/.env.example with new variables (IMAGE_POSTGRES_TEST, POSTGRES_TEST_PREBUILT, etc.)
9. Update documentation:
   - Add architecture layer explanation to docs/directory-structure.md
   - Update platform-infrastructure/README.md with test containers section
   - Consider creating docs/ARCHITECTURE.md for high-level layer explanation
10. Add tests (unit, integration, acceptance)
11. Verify with custom base images and prebuilt images
12. Merge to main

**Estimated effort:** 8-10 hours (includes documentation updates)

## Risks and Mitigations

### Risk: Migration breaks existing configs

**Mitigation:**
- Migration is idempotent
- Test with variety of existing configs
- Migration runs automatically, no manual steps
- Keeps process simple

### Risk: Dockerfile templates don't work with all corporate bases

**Mitigation:**
- Provide as templates, not rigid implementations
- Document customization points clearly
- Support both Alpine and Debian package managers in examples
- Test with multiple base images

### Risk: Test container builds fail in restricted networks

**Mitigation:**
- Support prebuilt image mode (no build needed)
- Document package mirror configuration
- Provide troubleshooting guide

## Success Criteria

### Phase 1

- [ ] All `services.postgres` references removed from codebase
- [ ] Migration runs automatically and successfully
- [ ] Old configs migrate cleanly to new structure
- [ ] All existing functionality works with new naming
- [ ] Clean-slate works with base_platform structure
- [ ] All tests pass

### Phase 2

- [ ] Wizard prompts for test container configuration
- [ ] Configuration saves to platform-config.yaml and .env
- [ ] Test containers build successfully from custom base images
- [ ] Progressive tests use configured test containers
- [ ] FreeTDS and unixODBC work in sqlcmd container
- [ ] DSN-based connections work
- [ ] Prebuilt image mode works
- [ ] All tests pass

## Future Enhancements

- Auto-detect if building is needed (check if images exist)
- Add validation to ensure test container images actually work
- Integrate test container builds into wizard flow (optional)
- Add more test containers (e.g., Redis client, MongoDB client)
- Support multi-stage builds for even smaller images

## References

- Existing Dockerfiles: `kerberos/kerberos-sidecar/Dockerfile.{postgres,sqlcmd}-test`
- Progressive tests: `wizard/services/kerberos/progressive_tests.py`
- Current postgres service: `wizard/services/postgres/`
- Platform config: `platform-config.yaml`
- Environment config: `platform-bootstrap/.env`
