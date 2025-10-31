# Kerberos Sidecar

Production-ready Kerberos authentication sidecar for Airflow containers, supporting both local development and Kubernetes deployment.

## Purpose

This sidecar container:
- Obtains Kerberos tickets using keytab or password authentication
- Automatically renews tickets before expiration
- Shares tickets with Airflow containers via shared volume
- Enables SQL Server Windows Authentication without passwords

## Minimal vs Legacy Images

We provide two image variants following strict separation of concerns:

| Image | Size | Packages | Purpose | Use Case |
|-------|------|----------|---------|----------|
| `platform/kerberos-sidecar:minimal` | 15.91 MB | 35 packages | **Production**: Ticket management ONLY | Deploy to prod/dev/staging |
| `platform/kerberos-sidecar:legacy` | 312 MB | 120+ packages | **Legacy**: Includes testing tools (bloated) | Backward compatibility only |

**Recommended**: Use `minimal` for production. Use separate test containers for connectivity validation.

**Key Benefits of Minimal Image**:
- 19x smaller than legacy (15.91 MB vs 312 MB)
- Reduced attack surface (35 vs 120+ packages = fewer CVEs)
- Single Responsibility: Manages Kerberos tickets, nothing else
- Aligns with corporate security best practices
- Faster pulls, lower storage costs, quicker deployments

**Migration**: See [MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md) for step-by-step legacy-to-minimal migration instructions.

## Quick Start

### Build the Image

**Build Minimal Image (Recommended):**
```bash
# Build using Dockerfile.minimal - production-ready, 15.91 MB
cd kerberos-sidecar
make build-minimal

# Creates: platform/kerberos-sidecar:minimal
```

**Build with automatic diagnostics:**
```bash
# Automatically checks requirements before building
make build-minimal
```

**Check requirements manually:**
```bash
# Run pre-build diagnostics without building
make check-requirements

# Shows:
# ✓ Docker accessibility
# ✓ Disk space availability
# ✓ Network connectivity (Docker Hub, Microsoft)
# ✓ Corporate proxy detection
# ✓ Build configuration preview
```

**Public internet (default):**
```bash
make build-minimal
```

**Corporate Artifactory:**
```bash
# Corporate configuration is in platform-bootstrap/.env (one place!)
# Your DevOps person likely already configured it in your fork

# 1. Verify configuration (already done in fork)
cat ../.env | grep IMAGE_ALPINE

# 2. Login to corporate registry
docker login artifactory.company.com

# 3. Build minimal image (uses parent .env automatically)
make build-minimal
```

**Chainguard Wolfi Base (Enhanced Security):**
```bash
# Chainguard images provide SLSA Level 3 provenance and regular security updates
# Requires authentication to cgr.dev

# 1. Login to Chainguard registry
docker login cgr.dev

# 2. Build with Chainguard Wolfi base
docker build -f Dockerfile \
  --build-arg IMAGE_ALPINE=cgr.dev/chainguard/wolfi-base:latest \
  -t platform/kerberos-sidecar:minimal .

# Corporate mirror example:
docker build -f Dockerfile \
  --build-arg IMAGE_ALPINE=artifactory.company.com/chainguard/wolfi-base:latest \
  -t platform/kerberos-sidecar:minimal .
```

Creates: `platform/kerberos-sidecar:minimal` in Docker cache (15.91 MB, 35 packages)

### Local Development Usage

**Using Minimal Sidecar (Recommended):**
```bash
# Start with docker-compose using minimal image
cd ../
docker compose -f developer-kerberos-standalone.yml up -d

# Verify minimal sidecar is running
docker logs kerberos-platform-service

# Check ticket
docker exec kerberos-platform-service klist

# Image in use: platform/kerberos-sidecar:minimal (15.91 MB)
```

### Kubernetes/Production Usage

See [Issue #23](https://github.com/Troubladore/airflow-data-platform/issues/23) for Kubernetes deployment patterns.

## Authentication Modes

### Password Authentication (Local Development)

```yaml
# docker-compose.yml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:minimal  # Use minimal image
    environment:
      - KRB_PRINCIPAL=user@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=your-password  # Or from secret
      - RENEWAL_INTERVAL=3600
```

### Keytab Authentication (Production/Kubernetes)

```yaml
# docker-compose.yml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:minimal  # Use minimal image
    environment:
      - KRB_PRINCIPAL=svc_airflow@COMPANY.COM
      - USE_PASSWORD=false
      - KRB_KEYTAB_PATH=/krb5/keytabs/airflow.keytab
      - RENEWAL_INTERVAL=3600
    volumes:
      - ./keytabs/airflow.keytab:/krb5/keytabs/airflow.keytab:ro
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `KRB_PRINCIPAL` | Yes | - | Kerberos principal (user@REALM) |
| `KRB_REALM` | No | Extracted from principal | Kerberos realm |
| `USE_PASSWORD` | No | `false` | Use password instead of keytab |
| `KRB_PASSWORD` | If USE_PASSWORD=true | - | Password for authentication |
| `KRB_KEYTAB_PATH` | If USE_PASSWORD=false | `/krb5/keytabs/service.keytab` | Path to keytab file |
| `RENEWAL_INTERVAL` | No | `3600` | Seconds between renewals |
| `KRB5_CONFIG` | No | `/etc/krb5.conf` | Kerberos config file |

### Volume Mounts

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| Shared cache | `/krb5/cache` | Write tickets here (rw) |
| Keytab (if used) | `/krb5/keytabs` | Keytab file (ro) |
| krb5.conf | `/krb5/conf` or `/etc/krb5.conf` | Kerberos config (ro) |

## Testing

### Basic Tests

```bash
# Run automated tests
make test

# Expected output:
# ✓ Image exists
# ✓ Kerberos tools present
# ✓ Ticket manager executable
```

### Integration Test

```bash
# Test full ticket acquisition flow
make integration-test

# Runs sidecar for 60 seconds with test credentials
```

### Manual Testing

```bash
# Start minimal sidecar interactively
docker run --rm -it \
  -e KRB_PRINCIPAL=test@TEST.COM \
  -e USE_PASSWORD=true \
  -e KRB_PASSWORD=testpass \
  platform/kerberos-sidecar:minimal /bin/bash

# Inside container:
/scripts/kerberos-ticket-manager.sh
```

## Test Containers (Separation of Concerns)

The minimal sidecar does **ONE thing well**: manage Kerberos tickets. For connectivity testing, use dedicated test containers.

### Why Separate Test Containers?

**Before (Legacy - Bloated):**
- Sidecar included sqlcmd, pyodbc, psql, etc. (312 MB, 120+ packages)
- Mixed concerns: ticket management + connectivity testing
- Large attack surface, more CVEs to patch

**After (Minimal - Clean):**
- Sidecar: Only Kerberos ticket management (15.91 MB, 35 packages)
- Test containers: Separate images for connectivity testing
- Clear separation: sidecar manages tickets, test containers consume them

### Available Test Containers

| Test Container | Size | Purpose | Tools Included |
|----------------|------|---------|----------------|
| `platform/sqlcmd-test` | ~100 MB | SQL Server testing | sqlcmd, bcp, msodbcsql18 |
| `platform/postgres-test` | ~50 MB | PostgreSQL GSSAPI testing | psql, krb5 |
| `platform/kerberos-test` | ~150 MB | Python DB testing | pyodbc, psycopg2, python3 |

### Using Test Containers

**Build test containers:**
```bash
# Build SQL Server test container
make build-sqlcmd-test

# Build PostgreSQL test container
make build-postgres-test

# Build Python test container
make build-test-image
```

**Test SQL Server connectivity:**
```bash
# Minimal sidecar manages tickets, sqlcmd-test consumes them
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"
```

**Test PostgreSQL GSSAPI connectivity:**
```bash
# Minimal sidecar manages tickets, postgres-test consumes them
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/postgres-test:latest \
  psql "host=postgres.company.com dbname=mydb gssencmode=require" -c "SELECT version()"
```

**Interactive testing session:**
```bash
# Start test container with shell access
docker run --rm -it \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  /bin/sh

# Inside container:
# - klist (verify tickets from sidecar)
# - sqlcmd -S <server> -E (test connections)
# - Run multiple queries
```

**Key Points:**
- Test containers mount ticket cache **read-only** from sidecar
- Test containers are **ephemeral** (run on-demand, not deployed to production)
- Sidecar stays minimal and focused on ticket management
- Add only the test containers you need for your use case

## Troubleshooting

### Build failures

```bash
# Run build diagnostics
make check-requirements

# Common build issues:
# - Docker not running: sudo systemctl start docker
# - Network blocked: Check corporate proxy/firewall
# - Insufficient disk space: docker system prune
# - Artifactory access: docker login artifactory.company.com
```

The build diagnostics tool (`scripts/check-build-requirements.sh`) provides:
- Specific failure mode detection (unauthorized, timeout, proxy, firewall)
- Exact fix commands for each issue
- Corporate proxy detection and guidance
- Color-coded status indicators

### Sidecar won't start

```bash
# Check logs
docker logs kerberos-platform-service

# Common issues:
# - Missing KRB_PRINCIPAL environment variable
# - Keytab file not found
# - krb5.conf not accessible
```

### Tickets not renewing

```bash
# Check renewal interval
docker exec kerberos-platform-service env | grep RENEWAL

# Check ticket expiration
docker exec kerberos-platform-service klist

# Verify renewal logic in logs
docker logs kerberos-platform-service | grep "renewal"
```

### Health check failing

```bash
# Test health check manually
docker exec kerberos-platform-service klist -s
echo $?  # Should be 0

# If fails:
docker exec kerberos-platform-service klist
# Shows detailed error
```

## Architecture

### Separation of Concerns: Minimal vs Legacy

**LEGACY ARCHITECTURE (Bloated - 312 MB):**
```
┌─────────────────────────────────────────────────────────────┐
│ Bloated Sidecar - 312 MB, 120+ packages                    │
│ ───────────────────────────────────────────────────────────  │
│                                                              │
│ ✓ Ticket Management (krb5, krb5-libs)        - NEEDED      │
│ ✗ Build Tools (gcc, g++, musl-dev)           - NOT NEEDED  │
│ ✗ Python (python3, py3-pip)                  - NOT NEEDED  │
│ ✗ ODBC (msodbcsql18, unixodbc)               - NOT NEEDED  │
│ ✗ SQL Tools (mssql-tools18, sqlcmd)          - NOT NEEDED  │
│ ✗ Dev Headers (*-dev packages)               - NOT NEEDED  │
│                                                              │
│ Problems:                                                    │
│ - Mixed responsibilities (ticket mgmt + testing)            │
│ - Large attack surface (120+ packages = more CVEs)         │
│ - Slow deployments (312 MB to pull)                        │
│ - Testing tools deployed to production unnecessarily        │
└─────────────────────────────────────────────────────────────┘
```

**MINIMAL ARCHITECTURE (Clean - 15.91 MB):**
```
┌──────────────────────────────────────────────────────────────┐
│ Minimal Sidecar - 15.91 MB, 35 packages (PRODUCTION)       │
│ ────────────────────────────────────────────────────────────  │
│                                                               │
│ ✓ Ticket Management (krb5, krb5-libs)        - NEEDED       │
│ ✓ Shell (bash)                               - NEEDED       │
│ ✓ Network (curl, ca-certificates)            - NEEDED       │
│                                                               │
│ Single Responsibility: Manage Kerberos tickets ONLY          │
│                                                               │
│ Benefits:                                                     │
│ - Minimal attack surface (35 packages, fewer CVEs)          │
│ - Fast deployments (15.91 MB - 19x smaller!)                │
│ - Production-ready (no testing tools in prod)                │
│ - Clear separation of concerns                               │
└──────────────────────────────────────────────────────────────┘
              │
              │ Writes tickets to shared volume
              ↓
┌──────────────────────────────────────────────────────────────┐
│ Shared Volume (Ticket Cache)                                │
│ /krb5/cache/krb5cc                                           │
└──────────────────────────────────────────────────────────────┘
              │
              ├─────────────────────┬──────────────────────────┐
              ↓                     ↓                          ↓
┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────────┐
│ Airflow Containers   │  │ Test Containers      │  │ Other Consumers     │
│ (Read-Only)          │  │ (Ephemeral)          │  │ (Read-Only)         │
│                      │  │                      │  │                     │
│ - KRB5CCNAME set     │  │ sqlcmd-test: 100 MB  │  │ - Custom apps       │
│ - Mounts cache:ro    │  │ postgres-test: 50 MB │  │ - DAGs              │
│ - Uses tickets for   │  │ kerberos-test: 150MB │  │ - Scripts           │
│   DB connections     │  │                      │  │                     │
│                      │  │ Run on-demand only!  │  │                     │
└──────────────────────┘  └──────────────────────┘  └─────────────────────┘
              │                     │                          │
              └─────────────────────┴──────────────────────────┘
                                    ↓
              ┌──────────────────────────────────────────────┐
              │ Backend Services (GSSAPI/Kerberos Auth)     │
              ├──────────────────────────────────────────────┤
              │ - SQL Server (Windows Auth)                 │
              │ - PostgreSQL (GSSAPI)                        │
              │ - Other Kerberized services                  │
              └──────────────────────────────────────────────┘
```

### Key Architectural Principles

1. **Single Responsibility**: Sidecar manages tickets, nothing else
2. **Separation of Concerns**: Testing tools in separate containers
3. **Least Privilege**: Minimal packages = minimal attack surface
4. **Read-Only Sharing**: Consumers mount ticket cache read-only
5. **On-Demand Testing**: Test containers run only when needed, not in production

### Ticket Lifecycle Flow

```
1. Minimal Sidecar starts
   ├── Reads KRB_PRINCIPAL, KRB_PASSWORD/KRB_KEYTAB
   ├── Obtains initial ticket via kinit
   └── Writes to /krb5/cache/krb5cc

2. Ticket Renewal Loop (every RENEWAL_INTERVAL seconds)
   ├── Check ticket validity: klist -s
   ├── If expired or near expiration: kinit (renew)
   └── Write renewed ticket to cache

3. Health Check (every 30s)
   ├── Run: klist -s
   ├── Exit 0: Ticket valid → Container healthy
   └── Exit 1: No ticket → Container unhealthy → Restart

4. Consumers Use Tickets
   ├── Airflow containers: KRB5CCNAME=/krb5/cache/krb5cc (read-only)
   ├── Test containers: Mount cache, run tests, exit
   └── Custom apps: Mount cache, use tickets for auth
```

## Files

- **Dockerfile.minimal** - Alpine 3.19 with Kerberos only (15.91 MB, 35 packages) - **RECOMMENDED**
- **Dockerfile.legacy** - Alpine 3.19 with Kerberos + ODBC + testing tools (312 MB, 120+ packages) - Legacy only
- **Dockerfile.sqlcmd-test** - SQL Server test container (separate from sidecar)
- **Dockerfile.postgres-test** - PostgreSQL test container (separate from sidecar)
- **Dockerfile.test-image** - Python test container (separate from sidecar)
- **scripts/kerberos-ticket-manager.sh** - Ticket lifecycle management
- **scripts/check-build-requirements.sh** - Pre-build diagnostics
- **Makefile** - Build, test, push commands
- **MIGRATION-GUIDE.md** - Legacy to minimal migration instructions
- **README.md** - This file

## Corporate Registry

### Alternative Base Images

The Dockerfile supports multiple base images via the `IMAGE_ALPINE` build argument:

| Base Image | Size Impact | Security Features | Use Case |
|------------|-------------|-------------------|----------|
| `alpine:3.19` (default) | 15 MB | Standard Alpine security | Public internet, default choice |
| `cgr.dev/chainguard/wolfi-base` | 34 MB | SLSA Level 3 provenance, signed images | Enhanced security, corporate compliance |
| Corporate Artifactory mirror | Varies | Depends on mirror configuration | Air-gapped environments, network restrictions |

**Why Chainguard Wolfi?**
- SLSA Level 3 supply chain security with signed provenance
- Regular security updates and CVE patching
- Verifiable build attestations
- Compatible with Alpine's apk package manager
- Meets enterprise security compliance requirements

**Build with different base images:**

```bash
# Default Alpine
docker build -f Dockerfile -t platform/kerberos-sidecar:minimal .

# Chainguard Wolfi (requires authentication)
docker login cgr.dev
docker build -f Dockerfile \
  --build-arg IMAGE_ALPINE=cgr.dev/chainguard/wolfi-base:latest \
  -t platform/kerberos-sidecar:minimal .

# Corporate Artifactory mirror
docker build -f Dockerfile \
  --build-arg IMAGE_ALPINE=artifactory.company.com/alpine:3.19 \
  -t platform/kerberos-sidecar:minimal .
```

**Note:** All base images must include the `apk` package manager and provide `krb5`, `krb5-libs`, `bash`, `curl`, and `ca-certificates` packages.

### Tagging for Kubernetes

```bash
# Tag for your corporate registry
make tag-for-k8s REGISTRY=registry.mycompany.com

# Push to registry
docker login registry.mycompany.com
make push REGISTRY=registry.mycompany.com
```

### Version Management

```bash
# Build with specific version tag
make build IMAGE_TAG=v1.0.0

# Tag for both latest and version
docker tag platform/kerberos-sidecar:latest platform/kerberos-sidecar:v1.0.0
```

## Security Considerations

- **Keytab files:** Mode 0600, never commit to git
- **Passwords:** Use Docker secrets, not environment variables in git
- **Ticket cache:** Shared volume, read-only for Airflow containers
- **Health checks:** Ensure tickets are valid, restart if not

## Links

- [Progressive Validation Guide](../docs/kerberos-progressive-validation.md) - Test your setup step-by-step
- [Issue #18](https://github.com/Troubladore/airflow-data-platform/issues/18) - Local development tracking
- [Issue #23](https://github.com/Troubladore/airflow-data-platform/issues/23) - Kubernetes deployment tracking
