# Test Container Migration Plan

**Date:** 2025-11-01
**Phase:** Phase 2 - Test Container Configuration (Task 1a - RED)
**Purpose:** Document what needs to change when migrating test containers to platform-infrastructure

---

## Current State Analysis

### Dockerfile.postgres-test (kerberos/kerberos-sidecar/)

**Current Implementation:**
- **Base Image:** Hardcoded `postgres:16-alpine`
- **Purpose:** PostgreSQL client with GSSAPI support for Kerberos authentication testing
- **Key Features:**
  - Uses postgres:16-alpine for GSSAPI-compiled psql client
  - Installs Kerberos client (krb5, krb5-libs)
  - Runs as root user (uid 0)
  - Alpine-based for minimal size
- **Dependencies:**
  - krb5
  - krb5-libs
  - ca-certificates

**Current Limitations:**
1. No BASE_IMAGE build argument - cannot customize base image
2. No unixODBC packages - limits database connectivity options
3. Runs as root user - security concern
4. Hardcoded to postgres:16-alpine - no corporate flexibility

### Dockerfile.sqlcmd-test (kerberos/kerberos-sidecar/)

**Current Implementation:**
- **Base Image:** Build argument `IMAGE_ALPINE` (default: alpine:3.19)
- **Purpose:** Microsoft sqlcmd for SQL Server testing with Kerberos
- **Key Features:**
  - Downloads Microsoft ODBC Driver 18 and SQL Server Tools 18
  - Uses MSSQL_TOOLS_URL build argument for corporate mirror support
  - Architecture detection (amd64/arm64)
  - Runs as root user (uid 0)
  - Requires .netrc for authenticated downloads
- **Dependencies:**
  - krb5
  - curl
  - msodbcsql18 (downloaded)
  - mssql-tools18 (downloaded)

**Current Limitations:**
1. Complex MSSQL_TOOLS_URL logic - can be simplified with modern approach
2. Runs as root user - security concern
3. Uses Microsoft proprietary tools - could use FreeTDS + unixODBC instead
4. Build argument naming inconsistent (IMAGE_ALPINE vs BASE_IMAGE)

---

## Required Changes

### 1. postgres-test Dockerfile Changes

**Location:** `platform-infrastructure/test-containers/postgres-test/Dockerfile`

#### Change 1.1: Add BASE_IMAGE Build Argument
**Current:**
```dockerfile
FROM postgres:16-alpine
```

**Required:**
```dockerfile
ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}
```

**Why:** Corporate environments may require custom base images from internal registries (e.g., `registry.corp.com/alpine:3.19-hardened`). Platform should support this flexibility.

#### Change 1.2: Add unixODBC Packages
**Current:**
```dockerfile
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    ca-certificates
```

**Required:**
```dockerfile
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    ca-certificates \
    postgresql-client \
    unixodbc \
    unixodbc-dev
```

**Why:**
- Must switch from postgres:16-alpine to alpine base (for BASE_IMAGE flexibility)
- Need to install postgresql-client explicitly
- unixODBC enables ODBC-based database connections
- Provides more flexibility for multi-database testing scenarios

#### Change 1.3: Add Non-Root User
**Current:**
```dockerfile
# (runs as root - no user specification)
```

**Required:**
```dockerfile
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

USER testuser
```

**Why:**
- Security best practice - containers should not run as root
- Corporate security policies often require non-root containers
- uid 10001 is in safe non-privileged range
- Prevents privilege escalation vulnerabilities

---

### 2. sqlcmd-test Dockerfile Changes

**Location:** `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`

#### Change 2.1: Standardize BASE_IMAGE Build Argument
**Current:**
```dockerfile
ARG IMAGE_ALPINE
FROM ${IMAGE_ALPINE:-alpine:3.19}
```

**Required:**
```dockerfile
ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}
```

**Why:** Consistent naming across all platform Dockerfiles. BASE_IMAGE is the standard pattern used elsewhere in the platform.

#### Change 2.2: Remove MSSQL_TOOLS_URL Complexity
**Current:**
```dockerfile
ARG MSSQL_TOOLS_URL
RUN --mount=type=secret,id=netrc,target=/root/.netrc \
    # Complex logic to download from Microsoft or corporate mirror
    # Architecture detection
    # Conditional URL construction
    # Download msodbcsql18 and mssql-tools18
```

**Required:**
```dockerfile
RUN apk add --no-cache \
    krb5 \
    unixodbc \
    freetds \
    freetds-dev
```

**Why:**
- **Simplification:** FreeTDS + unixODBC is open source and available in Alpine repos
- **No downloads:** No need for MSSQL_TOOLS_URL, .netrc authentication, or architecture detection
- **Corporate friendly:** Uses standard Alpine packages that corporate mirrors already cache
- **EULA-free:** No Microsoft license acceptance required
- **Functionally equivalent:** FreeTDS provides full SQL Server connectivity via ODBC
- **Easier maintenance:** No version pinning to Microsoft releases

#### Change 2.3: Add Non-Root User
**Current:**
```dockerfile
# (runs as root - no user specification)
```

**Required:**
```dockerfile
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

USER testuser
```

**Why:** Same security rationale as postgres-test.

---

## Why These Changes Matter

### 1. Corporate Flexibility
**Problem:** Organizations with air-gapped environments or strict registry policies cannot customize base images.

**Solution:**
- BASE_IMAGE build argument allows using corporate-approved base images
- Example: `--build-arg BASE_IMAGE=registry.corp.com/alpine:3.19-fips`

**Impact:** Platform can be deployed in any corporate environment without modification.

### 2. Security Hardening
**Problem:** Running containers as root violates security best practices and corporate policies.

**Solution:**
- Non-root user (testuser, uid 10001)
- Minimal privileges for test operations

**Impact:**
- Passes corporate security scans
- Reduces attack surface
- Complies with principle of least privilege

### 3. Simplification and Maintainability
**Problem:** MSSQL_TOOLS_URL logic is complex and brittle.

**Solution:**
- Use FreeTDS from Alpine repos
- Eliminate custom download logic
- Remove .netrc authentication requirement
- Remove architecture detection complexity

**Impact:**
- Faster builds (no downloads)
- More reliable (no external dependencies)
- Easier debugging
- No EULA considerations

### 4. Standardization
**Problem:** Inconsistent patterns between Dockerfiles (IMAGE_ALPINE vs BASE_IMAGE).

**Solution:**
- Standard BASE_IMAGE argument across all containers
- Consistent user creation pattern
- Uniform package installation approach

**Impact:**
- Easier to understand and maintain
- Predictable behavior across services
- Better documentation

---

## Migration Strategy

### Phase 1: Create New Dockerfiles (Task 1b - GREEN)
1. Create `platform-infrastructure/test-containers/postgres-test/Dockerfile`
2. Create `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`
3. Test builds with default args: `docker build -t test .`
4. Test builds with custom args: `docker build --build-arg BASE_IMAGE=alpine:3.19 -t test .`

### Phase 2: Integration (Tasks 2-5)
1. Create wizard sub-spec for test container configuration
2. Add wizard actions to save configuration
3. Add Makefile targets for building test containers
4. Update environment configuration

### Phase 3: Validation (Task 9)
1. Create integration tests
2. Verify postgres-test can connect to PostgreSQL with Kerberos
3. Verify sqlcmd-test can connect to SQL Server with FreeTDS
4. Test both build modes (build vs prebuilt)

### Phase 4: Cleanup (Task 10)
1. Remove `kerberos/kerberos-sidecar/Dockerfile.postgres-test`
2. Remove `kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test`
3. Update all references to new locations

---

## Success Criteria

### Dockerfile Quality
- [ ] Both Dockerfiles build successfully with default args
- [ ] Both Dockerfiles build successfully with custom BASE_IMAGE
- [ ] Both containers run as non-root user (testuser)
- [ ] postgres-test includes psql, klist, and ODBC drivers
- [ ] sqlcmd-test includes FreeTDS sqlcmd alternative and ODBC drivers

### Security
- [ ] No containers run as root
- [ ] All users have explicit uid/gid (10001)
- [ ] Minimal package installation (no unnecessary tools)

### Simplification
- [ ] No complex download logic in sqlcmd-test
- [ ] No .netrc authentication required
- [ ] No architecture detection needed
- [ ] All dependencies from Alpine repos

### Corporate Compatibility
- [ ] BASE_IMAGE can be overridden at build time
- [ ] No hardcoded external URLs
- [ ] No Microsoft EULA acceptance required
- [ ] Works in air-gapped environments

---

## Next Steps

This is the RED phase - we have documented what needs to change and why. The next phase (Task 1b - GREEN) will implement these changes by creating the new Dockerfiles.

**Implementation blocked until:** This migration plan is reviewed and approved.

**After approval:** Proceed to Task 1b to create the new Dockerfiles following this plan.
