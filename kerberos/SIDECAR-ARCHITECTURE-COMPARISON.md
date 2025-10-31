# Kerberos Sidecar Architecture Comparison

> **Analysis Date**: October 30, 2025
> **Current Image Size**: 312.86 MB
> **Base Image**: Alpine 3.19

## Executive Summary

The current Kerberos sidecar implementation **violates separation of concerns** by bundling connectivity testing tools (msodbcsql18, mssql-tools18, unixodbc, freetds, Python) into what should be a pure ticket management container. The corporate approach correctly separates these responsibilities.

**Recommendation**: Refactor the sidecar to match corporate architecture - keep it minimal with only Kerberos ticket management, move connectivity tools to separate test containers.

## Architecture Comparison

### Corporate Approach (Chainguard/Wolfi-based)

```dockerfile
# Minimal sidecar - ONLY ticket management
FROM chainguard/wolfi-base

RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash \
    gnupg \
    libstdc++ \
    krb5-libs \
    krb5

# NO connectivity tools in sidecar!
# msodbcsql18, mssql-tools18, unixodbc, freetds go in separate test containers

ENV PATH="$PATH:/opt/mssql-tools18/bin"
ACCEPT_EULA=Y
```

**Characteristics**:
- ✅ Single Responsibility: Only manages Kerberos tickets
- ✅ Minimal footprint: Essential Kerberos libraries only
- ✅ Security-hardened base (Chainguard)
- ✅ Connectivity tools isolated in separate containers

### Current Implementation (Alpine-based)

```dockerfile
# Bloated sidecar - ticket management + connectivity tools
FROM alpine:3.19

# Kerberos packages (CORRECT)
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    krb5-conf \
    krb5-dev \
    bash \
    curl \
    gnupg

# Connectivity tools (SHOULD NOT BE HERE!)
    unixodbc \
    unixodbc-dev \
    freetds \
    freetds-dev \

# Build tools (DEFINITELY SHOULD NOT BE HERE!)
    python3 \
    py3-pip \
    gcc \
    g++ \
    musl-dev \
    libffi-dev \
    openssl-dev

# Microsoft tools (SHOULD BE IN TEST CONTAINER!)
RUN curl -O .../msodbcsql18_18.3.2.1-1_amd64.apk && \
    curl -O .../mssql-tools18_18.3.1.1-1_amd64.apk && \
    apk add msodbcsql18 mssql-tools18
```

**Problems**:
- ❌ Violates Single Responsibility Principle
- ❌ 312.86 MB image (should be < 50 MB)
- ❌ Includes build tools (gcc, g++, musl-dev) - not needed at runtime!
- ❌ Includes Python stack - not used by ticket manager
- ❌ Includes ODBC/SQL tools - should be in test containers
- ❌ Security: Larger attack surface, more CVEs to patch

## Package Analysis

### What SHOULD Be in Sidecar (Kerberos Ticket Management)

| Package | Purpose | Corporate | Current | Status |
|---------|---------|-----------|---------|--------|
| `krb5` | Kerberos client (kinit, klist) | ✅ | ✅ | **KEEP** |
| `krb5-libs` | Kerberos libraries | ✅ | ✅ | **KEEP** |
| `bash` | Script execution | ✅ | ✅ | **KEEP** |
| `curl` | Downloads (if needed) | ✅ | ✅ | **KEEP** |
| `gnupg` | Signature verification | ✅ | ✅ | **KEEP** |
| `libstdc++` | C++ runtime | ✅ | ✅ | **KEEP** |
| `ca-certificates` | TLS/HTTPS | ✅ | ✅ | **KEEP** |

**Minimal sidecar size estimate**: 40-60 MB

### What SHOULD NOT Be in Sidecar (Move to Test Containers)

| Package | Purpose | Size Impact | Should Go To |
|---------|---------|-------------|--------------|
| `msodbcsql18` | SQL Server ODBC driver | ~155 MB | `platform/sqlcmd-test` |
| `mssql-tools18` | sqlcmd, bcp | ~154 MB | `platform/sqlcmd-test` |
| `unixodbc` | ODBC driver manager | ~1 MB | Test containers |
| `unixodbc-dev` | Headers (build-time) | ~200 KB | **REMOVE** |
| `freetds` | TDS protocol | ~1 MB | Test containers |
| `freetds-dev` | Headers (build-time) | ~50 KB | **REMOVE** |
| `python3` | Python runtime | ~15 MB | **REMOVE** |
| `py3-pip` | Package installer | ~5 MB | **REMOVE** |
| `gcc` | C compiler (build-time!) | ~30 MB | **REMOVE** |
| `g++` | C++ compiler (build-time!) | ~40 MB | **REMOVE** |
| `musl-dev` | C library headers (build-time!) | ~5 MB | **REMOVE** |
| `libffi-dev` | FFI headers (build-time!) | ~200 KB | **REMOVE** |
| `openssl-dev` | SSL headers (build-time!) | ~3 MB | **REMOVE** |
| `krb5-dev` | Kerberos headers (build-time!) | ~500 KB | **REMOVE** |
| `krb5-conf` | Config examples | ~10 KB | Optional |
| `krb5-server-ldap` | Server components | ~500 KB | **REMOVE** |

**Total bloat**: ~250+ MB of unnecessary packages

## Existing Test Container Architecture

The repository already has the correct separation pattern defined!

### 1. SQL Server Test Container (`Dockerfile.sqlcmd-test`)

```dockerfile
FROM alpine:3.19

# ONLY Kerberos + SQL Server tools
RUN apk add --no-cache krb5 curl

# Install Microsoft ODBC + sqlcmd
RUN curl -O .../msodbcsql18.apk && \
    curl -O .../mssql-tools18.apk && \
    apk add msodbcsql18 mssql-tools18

ENV PATH="/opt/mssql-tools18/bin:${PATH}"
```

**Purpose**: Test SQL Server connections using tickets from sidecar
**Size**: ~100 MB (much smaller than 312 MB!)

### 2. Python Test Container (`Dockerfile.test-image`)

For Python-based connectivity testing (pyodbc, etc.)

**Purpose**: Test database connections via Python libraries
**Mounts**: Ticket cache from sidecar (read-only)

## Recommended Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Kerberos Sidecar (MINIMAL)                                  │
│ ────────────────────────────────────────────────────────── │
│ Base: chainguard/wolfi-base OR alpine:3.19                  │
│ Packages: krb5, krb5-libs, bash, curl, ca-certificates     │
│ Size: 40-60 MB                                              │
│                                                              │
│ Purpose:                                                     │
│  - Obtain Kerberos tickets (kinit)                          │
│  - Renew tickets automatically                              │
│  - Share tickets via /krb5/cache volume                     │
│                                                              │
│ Does NOT include:                                            │
│  ✗ ODBC drivers                                             │
│  ✗ SQL tools (sqlcmd, bcp)                                  │
│  ✗ Python                                                    │
│  ✗ Build tools (gcc, g++)                                   │
│  ✗ Development headers (*-dev packages)                     │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Shares tickets via volume
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Test Container 1: platform/sqlcmd-test                      │
│ ────────────────────────────────────────────────────────── │
│ Base: alpine:3.19                                            │
│ Packages: krb5, krb5-libs, msodbcsql18, mssql-tools18      │
│ Size: ~100 MB                                               │
│                                                              │
│ Purpose:                                                     │
│  - Test SQL Server connections                              │
│  - Uses tickets FROM sidecar (read-only mount)             │
│  - sqlcmd, bcp available                                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Test Container 2: platform/kerberos-test (Python)          │
│ ────────────────────────────────────────────────────────── │
│ Base: python:3.11-alpine                                     │
│ Packages: krb5, pyodbc, psycopg2 (via pip)                 │
│ Size: ~150 MB                                               │
│                                                              │
│ Purpose:                                                     │
│  - Test Python database connections                         │
│  - Uses tickets FROM sidecar (read-only mount)             │
│  - Libraries: pyodbc, psycopg2, etc.                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Test Container 3: platform/postgres-test                    │
│ ────────────────────────────────────────────────────────── │
│ Base: alpine:3.19                                            │
│ Packages: krb5, postgresql-client                           │
│ Size: ~50 MB                                                │
│                                                              │
│ Purpose:                                                     │
│  - Test PostgreSQL GSSAPI connections                       │
│  - Uses tickets FROM sidecar (read-only mount)             │
│  - psql available                                            │
└─────────────────────────────────────────────────────────────┘
```

## Why Separation Matters

### 1. **Single Responsibility Principle**
- Sidecar: One job - manage Kerberos tickets
- Test containers: One job each - test specific connectivity

### 2. **Security**
- Smaller sidecar = fewer CVEs to patch
- Minimal attack surface in production
- Build tools (gcc, g++) are attack vectors if present at runtime

### 3. **Image Size**
- Current sidecar: 312.86 MB
- Proposed sidecar: ~50 MB (6x smaller!)
- Test containers: Build only when needed, not deployed to prod

### 4. **Deployment Flexibility**
- Production: Deploy only minimal sidecar
- Testing: Spin up test containers on-demand
- Development: Choose which test tools you need

### 5. **Maintenance**
- Update SQL tools? Only rebuild test container
- Update Kerberos? Only rebuild sidecar
- Clear separation of concerns

## Current vs Proposed Package Counts

### Current Sidecar
```
Total packages: 120+
Categories:
  - Kerberos: 7 packages ✓ (needed)
  - Build tools: 15 packages ✗ (remove!)
  - ODBC/SQL: 4 packages ✗ (move to test container)
  - Python: 12 packages ✗ (remove!)
  - Development headers: 10+ packages ✗ (remove!)
  - System libraries: 60+ packages (some needed, many not)
```

### Proposed Minimal Sidecar
```
Total packages: 15-20
Categories:
  - Kerberos: 7 packages (krb5, krb5-libs, etc.)
  - Shell/utilities: 5 packages (bash, curl, coreutils)
  - TLS/crypto: 3 packages (ca-certificates, openssl)
  - System essentials: 5 packages (musl, zlib, etc.)
```

## Migration Path

### Phase 1: Create Minimal Sidecar (New Dockerfile)

```dockerfile
# Dockerfile.minimal
ARG IMAGE_ALPINE
FROM ${IMAGE_ALPINE:-alpine:3.19}

# ONLY Kerberos essentials
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    bash \
    curl \
    ca-certificates

# Create directories
RUN mkdir -p /krb5/conf /krb5/cache /krb5/keytabs /scripts

# Copy ticket management scripts
COPY scripts/kerberos-ticket-manager.sh /scripts/
COPY scripts/health-check.sh /scripts/
RUN chmod +x /scripts/*.sh

# Kerberos environment
ENV KRB5_CONFIG=/krb5/conf/krb5.conf \
    KRB5CCNAME=/krb5/cache/krb5cc

# Health check
HEALTHCHECK --interval=30s --timeout=10s \
    CMD klist -s || exit 1

CMD ["/scripts/kerberos-ticket-manager.sh"]
```

**Expected size**: 40-50 MB

### Phase 2: Keep Current Dockerfile for Legacy/Testing

```bash
# Rename current Dockerfile
mv Dockerfile Dockerfile.legacy

# Use minimal for production
mv Dockerfile.minimal Dockerfile
```

### Phase 3: Document Test Container Usage

Update README to show:
1. Use minimal sidecar for production
2. Use test containers for connectivity validation
3. Mount ticket cache read-only in test containers

## Corporate Alignment Checklist

| Requirement | Corporate | Current | After Refactor |
|-------------|-----------|---------|----------------|
| **Base Image** | Chainguard/Wolfi | Alpine 3.19 | Alpine or Chainguard |
| **Minimal Packages** | Yes | ❌ No (120+) | ✅ Yes (15-20) |
| **ca-certificates** | ✅ Required | ✅ Present | ✅ Keep |
| **curl** | ✅ Required | ✅ Present | ✅ Keep |
| **bash** | ✅ Required | ✅ Present | ✅ Keep |
| **gnupg** | ✅ Required | ✅ Present | ✅ Keep (optional) |
| **libstdc++** | ✅ Required | ✅ Present | ✅ Keep |
| **krb5-libs** | ✅ Required | ✅ Present | ✅ Keep |
| **krb5** | ✅ Required | ✅ Present | ✅ Keep |
| **msodbcsql18** | ❌ Separate container | ❌ In sidecar | ✅ Move to test |
| **mssql-tools18** | ❌ Separate container | ❌ In sidecar | ✅ Move to test |
| **unixodbc** | ❌ Separate container | ❌ In sidecar | ✅ Move to test |
| **freetds** | ❌ Separate container | ❌ In sidecar | ✅ Move to test |
| **ACCEPT_EULA** | ✅ Set | ❌ Not set | ✅ Add to test containers |
| **PATH** | ✅ mssql-tools in PATH | ✅ Already set | ✅ Move to test containers |
| **Build tools** | ❌ Not included | ❌ Included | ✅ Remove |
| **Python** | ❌ Not included | ❌ Included | ✅ Remove |

## Differences from Corporate Approach

### We're Doing RIGHT

1. ✅ **Separate test containers exist** (`Dockerfile.sqlcmd-test`, `Dockerfile.test-image`)
2. ✅ **Corporate registry support** (IMAGE_ALPINE build arg)
3. ✅ **Artifactory mirroring** (ODBC_DRIVER_URL build arg)
4. ✅ **Ticket sharing via volume** (correct pattern)
5. ✅ **Health checks** (klist -s)

### We're Doing WRONG

1. ❌ **Bloated sidecar** (312 MB vs should be ~50 MB)
2. ❌ **Build tools at runtime** (gcc, g++, musl-dev)
3. ❌ **Development headers** (krb5-dev, unixodbc-dev, etc.)
4. ❌ **Python in sidecar** (not used by ticket manager)
5. ❌ **ODBC/SQL tools in sidecar** (should only be in test containers)
6. ❌ **No ACCEPT_EULA** (required for msodbcsql18)

### Corporate Uses Chainguard/Wolfi, We Use Alpine

**Corporate Rationale**:
- Chainguard images are security-hardened
- Minimal CVE surface
- Designed for production workloads

**Our Situation**:
- Alpine is acceptable for testing
- For production, consider switching to Chainguard base
- OR keep Alpine minimal (current approach works if cleaned up)

**Recommendation**:
1. Keep Alpine for now (it's fine if minimal)
2. Add Chainguard support via build arg (for corporate deployments)
3. Focus on removing bloat first (bigger win than base image swap)

## Action Items

### Immediate (High Priority)

1. ✅ **Document the issue** (this file)
2. ⬜ **Create Dockerfile.minimal** (pure ticket management)
3. ⬜ **Build and test minimal image** (verify < 60 MB)
4. ⬜ **Update test container docs** (how to use with minimal sidecar)
5. ⬜ **Add ACCEPT_EULA=Y** to test container Dockerfiles

### Short-term (Medium Priority)

6. ⬜ **Rename current Dockerfile** → Dockerfile.legacy
7. ⬜ **Promote Dockerfile.minimal** → Dockerfile
8. ⬜ **Update CI/CD** to build both images (minimal for prod, legacy for compat)
9. ⬜ **Create postgres-test container** (psql + krb5)
10. ⬜ **Document migration path** for users on legacy image

### Long-term (Low Priority)

11. ⬜ **Add Chainguard/Wolfi base** (via IMAGE_ALPINE build arg)
12. ⬜ **Security scanning** (compare CVEs: Alpine vs Chainguard)
13. ⬜ **Performance testing** (minimal vs legacy startup time)
14. ⬜ **Kubernetes manifests** (sidecar pattern examples)

## Questions for Corporate Environment Discussion

1. **Base Image**: Is Chainguard/Wolfi required, or can we use minimal Alpine?
2. **Package Repository**: Do we need to mirror APK packages in Artifactory?
3. **ACCEPT_EULA**: How is EULA acceptance handled in corporate environment?
4. **Image Registry**: Where should minimal sidecar be published?
5. **CVE Scanning**: What's the acceptable CVE threshold for production images?

## Conclusion

**Current State**: The Kerberos sidecar violates separation of concerns by including ~250 MB of unnecessary packages (ODBC drivers, SQL tools, Python, build tools) that belong in separate test containers.

**Corporate Approach**: Correctly separates ticket management (sidecar) from connectivity testing (separate containers).

**Gap**: We have the right architecture (test containers exist!), but we're not using it. The sidecar is bloated because it was built for "all-in-one" convenience instead of production deployment.

**Recommendation**:
1. Create `Dockerfile.minimal` with ONLY Kerberos packages (~50 MB)
2. Keep `Dockerfile.sqlcmd-test` and `Dockerfile.test-image` for testing
3. Document the separation of concerns
4. Consider Chainguard base for corporate deployments

**Impact**:
- 6x smaller production image (312 MB → 50 MB)
- Reduced attack surface (120+ packages → 15-20 packages)
- Aligned with corporate best practices
- Faster deployments, fewer CVEs to patch
