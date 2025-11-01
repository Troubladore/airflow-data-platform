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

## Design Goals

1. Correct the architectural naming (postgres → base_platform)
2. Enable wizard configuration of test container images
3. Provide minimal Dockerfile templates for corporate users
4. Support both "build from base" and "use prebuilt" workflows
5. Maintain clean migration path (no permanent backward compatibility)
6. Store configuration persistently across wizard sessions

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

#### 1. Minimal Dockerfile Templates

Provide reference implementations as templates for corporate users to customize.

**`kerberos/kerberos-sidecar/Dockerfile.postgres-test.minimal`:**
```dockerfile
# Minimal PostgreSQL + Kerberos Test Container
# ==============================================
# Template for corporate environments with restricted base images
# Customize BASE_IMAGE to match your approved registry

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install PostgreSQL client with GSSAPI + Kerberos tools
# Adjust package names for your base (Alpine shown)
RUN apk update && apk add --no-cache \
    postgresql17-client \
    krb5 krb5-libs krb5-conf \
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
- Explicitly pinned package versions (shown in comments)
- Non-root user for security
- Minimal layer count
- ~50MB compressed (vs ~230MB for postgres:16-alpine)

**`kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test.minimal`:**
```dockerfile
# Minimal SQL Server + Kerberos Test Container
# ==============================================
# Template for corporate environments with restricted base images

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

# Install Microsoft SQL Server tools
# For corporate environments, set MSSQL_TOOLS_URL to internal mirror
ARG MSSQL_TOOLS_URL
RUN arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    base_url="${MSSQL_TOOLS_URL:-https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8}" && \
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
- Parameterized `MSSQL_TOOLS_URL` for corporate mirrors
- Microsoft EULA acceptance documented
- Non-root user

**Why FreeTDS + unixODBC:**
- FreeTDS provides fallback if Microsoft driver has issues
- unixODBC enables DSN-based connections for cleaner connection strings
- `odbcinst -q -d` helps troubleshoot driver registration issues

#### 2. Wizard Sub-Spec

**`wizard/services/base_platform/test-containers-spec.yaml`:**
```yaml
# Test container configuration for base platform
# Invoked from main base_platform/spec.yaml

steps:
  - id: postgres_test_mode
    type: boolean
    state_key: services.base_platform.test_containers.postgres_test.build_from_base
    default_from: services.base_platform.test_containers.postgres_test.build_from_base
    prompt: "Build PostgreSQL test container from base image (vs. using prebuilt)?"
    default_value: true
    next: postgres_test_image

  - id: postgres_test_image
    type: string
    state_key: services.base_platform.test_containers.postgres_test.base_image
    default_from: services.base_platform.test_containers.postgres_test.base_image
    prompt: "Base image for PostgreSQL test container (e.g., alpine:3.22):"
    default_value: "alpine:latest"
    condition: "state.services.base_platform.test_containers.postgres_test.build_from_base == true"
    next: sqlcmd_test_mode

  - id: postgres_test_prebuilt
    type: string
    state_key: services.base_platform.test_containers.postgres_test.prebuilt_image
    default_from: services.base_platform.test_containers.postgres_test.prebuilt_image
    prompt: "Prebuilt PostgreSQL test image (e.g., mycorp.io/postgres-test:latest):"
    condition: "state.services.base_platform.test_containers.postgres_test.build_from_base == false"
    next: sqlcmd_test_mode

  - id: sqlcmd_test_mode
    type: boolean
    state_key: services.base_platform.test_containers.sqlcmd_test.build_from_base
    default_from: services.base_platform.test_containers.sqlcmd_test.build_from_base
    prompt: "Build SQL Server test container from base image (vs. using prebuilt)?"
    default_value: true
    next: sqlcmd_test_image

  - id: sqlcmd_test_image
    type: string
    state_key: services.base_platform.test_containers.sqlcmd_test.base_image
    default_from: services.base_platform.test_containers.sqlcmd_test.base_image
    prompt: "Base image for SQL Server test container (e.g., alpine:3.22):"
    default_value: "alpine:latest"
    condition: "state.services.base_platform.test_containers.sqlcmd_test.build_from_base == true"
    next: sqlcmd_tools_url

  - id: sqlcmd_test_prebuilt
    type: string
    state_key: services.base_platform.test_containers.sqlcmd_test.prebuilt_image
    default_from: services.base_platform.test_containers.sqlcmd_test.prebuilt_image
    prompt: "Prebuilt SQL Server test image (e.g., mycorp.io/sqlcmd-test:latest):"
    condition: "state.services.base_platform.test_containers.sqlcmd_test.build_from_base == false"
    next: save_test_config

  - id: sqlcmd_tools_url
    type: string
    state_key: services.base_platform.test_containers.sqlcmd_test.mssql_tools_url
    default_from: services.base_platform.test_containers.sqlcmd_test.mssql_tools_url
    prompt: "Microsoft SQL Server tools URL (leave empty for default, or corporate mirror):"
    default_value: ""
    condition: "state.services.base_platform.test_containers.sqlcmd_test.build_from_base == true"
    next: save_test_config

  - id: save_test_config
    type: action
    action: base_platform.save_test_container_config
    next: finish
```

**Flow Logic:**
1. Ask if building from base or using prebuilt (postgres)
2. If building: prompt for base image
3. If prebuilt: prompt for prebuilt image path
4. Repeat for sqlcmd
5. For sqlcmd build mode: optionally configure MSSQL tools URL
6. Save configuration

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
        build_from_base: true
        base_image: "mycorp.jfrog.io/approved/alpine:3.22"
        # OR
        # build_from_base: false
        # prebuilt_image: "mycorp.jfrog.io/test-images/postgres-test:v1"

      sqlcmd_test:
        build_from_base: true
        base_image: "mycorp.jfrog.io/approved/alpine:3.22"
        mssql_tools_url: "https://artifacts.mycorp.com/mssql-tools/"
```

**`platform-bootstrap/.env`:**
```bash
# PostgreSQL (base platform)
IMAGE_POSTGRES=postgres:17.5-alpine
PLATFORM_DB_USER=platform_admin
PLATFORM_DB_PASSWORD=changeme

# Test containers
IMAGE_POSTGRES_TEST_BASE=mycorp.jfrog.io/approved/alpine:3.22
POSTGRES_TEST_BUILD_FROM_BASE=true
IMAGE_SQLCMD_TEST_BASE=mycorp.jfrog.io/approved/alpine:3.22
SQLCMD_TEST_BUILD_FROM_BASE=true
MSSQL_TOOLS_URL=https://artifacts.mycorp.com/mssql-tools/
```

#### 5. Build Integration

Update Dockerfiles to use configured values via build args:

**Example build command:**
```bash
docker build \
  -f kerberos/kerberos-sidecar/Dockerfile.postgres-test.minimal \
  --build-arg BASE_IMAGE=${IMAGE_POSTGRES_TEST_BASE} \
  -t platform/postgres-test:latest .
```

**Makefile integration:**
```makefile
build-postgres-test:
	@if [ -f .env ]; then source .env; fi && \
	docker build \
	  -f kerberos/kerberos-sidecar/Dockerfile.postgres-test.minimal \
	  --build-arg BASE_IMAGE=$${IMAGE_POSTGRES_TEST_BASE:-alpine:latest} \
	  -t platform/postgres-test:latest .

build-sqlcmd-test:
	@if [ -f .env ]; then source .env; fi && \
	docker build \
	  -f kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test.minimal \
	  --build-arg BASE_IMAGE=$${IMAGE_SQLCMD_TEST_BASE:-alpine:latest} \
	  --build-arg MSSQL_TOOLS_URL=$${MSSQL_TOOLS_URL:-} \
	  -t platform/sqlcmd-test:latest .
```

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
2. Create minimal Dockerfile templates
3. Create test-containers-spec.yaml
4. Implement save_test_container_config action
5. Update main spec to invoke sub-spec
6. Update Makefile with build targets
7. Update .env.example with new variables
8. Add tests
9. Verify with custom base images
10. Merge to main

**Estimated effort:** 6-8 hours

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
