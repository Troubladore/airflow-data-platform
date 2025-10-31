# Migration Guide: Legacy to Minimal Kerberos Sidecar

> **Migration Date**: October 30, 2025
> **Legacy Image Size**: 312 MB (120+ packages)
> **Minimal Image Size**: 16 MB (15-20 packages)
> **Recommended Approach**: Staged migration with rollback plan

## Table of Contents

1. [Why Migrate?](#why-migrate)
2. [Migration Steps](#migration-steps)
3. [Using Test Containers](#using-test-containers)
4. [Rollback Plan](#rollback-plan)
5. [Troubleshooting Common Issues](#troubleshooting-common-issues)
6. [Validation Checklist](#validation-checklist)

---

## Why Migrate?

### Rationale and Benefits

The minimal Kerberos sidecar refactor addresses critical architectural and security concerns:

#### 1. **Dramatic Size Reduction**
- **Legacy**: 312 MB with 120+ packages
- **Minimal**: 16 MB with 15-20 packages
- **Benefit**: 19x smaller! Faster pulls, lower storage costs, quicker deployments

#### 2. **Security Hardening**
- **Removed**: Build tools (gcc, g++, musl-dev) that are attack vectors at runtime
- **Removed**: 100+ unnecessary packages = 100+ fewer CVE risks to patch
- **Minimal attack surface**: Only Kerberos essentials remain

#### 3. **Single Responsibility Principle**
- **Legacy**: Sidecar tries to do everything (ticket management + connectivity testing)
- **Minimal**: Sidecar does ONE thing well - manages Kerberos tickets
- **Separation of Concerns**: Test containers handle connectivity validation

#### 4. **Corporate Alignment**
- **Pattern**: Matches corporate architecture (Chainguard/Wolfi-based minimal sidecars)
- **Best Practice**: Separate ticket management from connectivity testing
- **Compliance**: Easier to audit, fewer compliance risks

#### 5. **Deployment Flexibility**
- **Production**: Deploy only minimal sidecar (16 MB)
- **Testing**: Spin up test containers on-demand (not deployed to prod)
- **Development**: Choose which test tools you need when you need them

---

## Migration Steps

### Prerequisites

Before starting migration:

```bash
# 1. Verify Docker is running
docker --version

# 2. Check disk space (need ~500 MB for build process)
df -h /var/lib/docker

# 3. Backup current configuration
cp docker-compose.yml docker-compose.yml.backup

# 4. Ensure you have access to image registry (if using corporate Artifactory)
docker login artifactory.company.com  # If applicable
```

### Step 1: Build the Minimal Sidecar

```bash
cd /path/to/kerberos-sidecar

# Build minimal image
make build-minimal

# Expected output:
# ✓ Building platform/kerberos-sidecar:minimal
# ✓ Image size: ~16 MB
# ✓ Package count: 15-20

# Verify the image
docker images | grep kerberos-sidecar
# Should show:
# platform/kerberos-sidecar    minimal    <hash>   16 MB
# platform/kerberos-sidecar    legacy     <hash>   312 MB  (old one)
```

### Step 2: Update Your docker-compose.yml

**Before (Legacy):**
```yaml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:latest  # 312 MB bloated image
    environment:
      - KRB_PRINCIPAL=user@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=${KRB_PASSWORD}
      - RENEWAL_INTERVAL=3600
    volumes:
      - kerberos-cache:/krb5/cache
      - ./krb5.conf:/krb5/conf/krb5.conf:ro
```

**After (Minimal):**
```yaml
services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:minimal  # 16 MB minimal image
    environment:
      - KRB_PRINCIPAL=user@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=${KRB_PASSWORD}
      - RENEWAL_INTERVAL=3600
    volumes:
      - kerberos-cache:/krb5/cache
      - ./krb5.conf:/krb5/conf/krb5.conf:ro
```

**Key Changes**:
- Image tag: `latest` → `minimal`
- No other configuration changes required!
- All environment variables stay the same
- Volume mounts stay the same

### Step 3: Test the Minimal Sidecar

```bash
# Start minimal sidecar
docker compose up -d kerberos-sidecar

# Verify it's running
docker ps | grep kerberos-sidecar

# Check logs for successful ticket acquisition
docker logs kerberos-sidecar
# Expected output:
# ✓ Acquired ticket for user@COMPANY.COM
# ✓ Ticket valid until <timestamp>
# ✓ Renewal scheduled in 3600 seconds

# Verify ticket cache
docker exec kerberos-sidecar klist
# Expected output:
# Ticket cache: FILE:/krb5/cache/krb5cc
# Default principal: user@COMPANY.COM
# Valid starting       Expires              Service principal
# 10/30/25 10:00:00  10/30/25 20:00:00  krbtgt/COMPANY.COM@COMPANY.COM
```

### Step 4: Migrate Connectivity Testing to Test Containers

The minimal sidecar **no longer includes** connectivity tools. Use separate test containers instead.

#### For SQL Server Testing

**Before (Legacy):**
```bash
# Legacy: sqlcmd was baked into sidecar
docker exec kerberos-sidecar sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"
```

**After (Minimal + Test Container):**
```bash
# Build SQL Server test container
make build-sqlcmd-test

# Run sqlcmd using test container (mounts ticket cache from sidecar)
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"
```

**What Changed**:
- sqlcmd moved FROM sidecar TO separate test container
- Test container mounts ticket cache read-only from sidecar
- Sidecar only manages tickets, test container only tests connectivity

#### For PostgreSQL Testing

**Build and use PostgreSQL test container:**

```bash
# Build postgres test container
make build-postgres-test

# Test PostgreSQL GSSAPI connection
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/postgres-test:latest \
  psql "host=postgres.company.com dbname=mydb user=user@COMPANY.COM gssencmode=require"
```

#### For Python/pyodbc Testing

**Build and use Python test container:**

```bash
# Build Python test container
make build-test-image

# Test Python ODBC connection
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -v $(pwd)/test-script.py:/app/test.py \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/kerberos-test:latest \
  python /app/test.py
```

### Step 5: Update CI/CD Pipelines

If you have automated builds:

```yaml
# .gitlab-ci.yml or similar
build:
  script:
    # Change from:
    - docker build -t platform/kerberos-sidecar:latest .

    # To:
    - docker build -f Dockerfile.minimal -t platform/kerberos-sidecar:minimal .

    # Optional: Keep legacy for compatibility
    - docker build -f Dockerfile.legacy -t platform/kerberos-sidecar:legacy .
```

---

## Using Test Containers

Test containers are ephemeral, single-purpose containers that mount the ticket cache from the minimal sidecar.

### Test Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Minimal Sidecar (platform/kerberos-sidecar:minimal)        │
│ ─────────────────────────────────────────────────────────── │
│ - Size: 16 MB                                                │
│ - Purpose: Manage Kerberos tickets ONLY                     │
│ - Packages: krb5, krb5-libs, bash, curl, ca-certificates   │
│                                                              │
│ Writes tickets to: /krb5/cache/krb5cc                       │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Shares via named volume
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Test Containers (run on-demand, not in production)         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ 1. platform/sqlcmd-test                                     │
│    - Purpose: SQL Server connectivity testing               │
│    - Tools: sqlcmd, bcp, msodbcsql18                        │
│    - Size: ~100 MB                                          │
│    - Mounts: /krb5/cache:ro (read-only)                     │
│                                                              │
│ 2. platform/kerberos-test (Python)                          │
│    - Purpose: Python database testing                       │
│    - Tools: pyodbc, psycopg2                                │
│    - Size: ~150 MB                                          │
│    - Mounts: /krb5/cache:ro (read-only)                     │
│                                                              │
│ 3. platform/postgres-test                                   │
│    - Purpose: PostgreSQL GSSAPI testing                     │
│    - Tools: psql, krb5                                      │
│    - Size: ~50 MB                                           │
│    - Mounts: /krb5/cache:ro (read-only)                     │
└─────────────────────────────────────────────────────────────┘
```

### Before and After Comparison

```
BEFORE (Legacy Architecture):
┌────────────────────────────────────────────────────────────┐
│ Bloated Sidecar - 312 MB                                   │
│ ─────────────────────────────────────────────────────────  │
│ ✓ Kerberos (krb5, krb5-libs)              - Needed        │
│ ✗ Build Tools (gcc, g++, musl-dev)        - NOT needed    │
│ ✗ Python (python3, py3-pip)               - NOT needed    │
│ ✗ ODBC (msodbcsql18, unixodbc)            - NOT needed    │
│ ✗ SQL Tools (mssql-tools18, sqlcmd)       - NOT needed    │
│ ✗ Dev Headers (*-dev packages)            - NOT needed    │
│                                                             │
│ Packages: 120+                                              │
│ Attack Surface: HIGH (many CVEs to patch)                  │
│ Purpose: Confused (ticket mgmt + testing)                  │
└────────────────────────────────────────────────────────────┘

AFTER (Minimal Architecture):
┌────────────────────────────────────────────────────────────┐
│ Minimal Sidecar - 16 MB                                    │
│ ─────────────────────────────────────────────────────────  │
│ ✓ Kerberos (krb5, krb5-libs)              - Needed        │
│ ✓ Shell (bash)                            - Needed        │
│ ✓ Network (curl, ca-certificates)         - Needed        │
│                                                             │
│ Packages: 15-20                                             │
│ Attack Surface: MINIMAL (few CVEs to patch)                │
│ Purpose: CLEAR (ticket management only)                    │
└────────────────────────────────────────────────────────────┘
         +
┌────────────────────────────────────────────────────────────┐
│ Test Containers (ephemeral, on-demand)                    │
│ ─────────────────────────────────────────────────────────  │
│ sqlcmd-test:      100 MB  (SQL Server testing)             │
│ kerberos-test:    150 MB  (Python testing)                 │
│ postgres-test:     50 MB  (PostgreSQL testing)             │
│                                                             │
│ Deployment: NOT deployed to production                     │
│ Usage: Developer workstations, CI/CD only                  │
└────────────────────────────────────────────────────────────┘

Result:
  - Production image: 312 MB → 16 MB (19x smaller!)
  - Security: 120+ packages → 15-20 packages
  - Purpose: Clear separation of concerns
```

### Test Container Usage Patterns

#### Pattern 1: One-off Connection Test

```bash
# Test SQL Server connection
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  sqlcmd -S sqlserver.company.com -E -Q "SELECT 1"
```

#### Pattern 2: Interactive Testing Session

```bash
# Start interactive shell in test container
docker run --rm -it \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  /bin/sh

# Inside container:
# - klist (verify tickets)
# - sqlcmd -S <server> -E (test connections)
# - Run multiple queries
```

#### Pattern 3: Scripted Test Suite

```bash
# test-connectivity.sh
#!/bin/bash

# Build test containers
make build-sqlcmd-test
make build-postgres-test

# Test SQL Server
echo "Testing SQL Server..."
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  platform/sqlcmd-test:latest \
  sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"

# Test PostgreSQL
echo "Testing PostgreSQL..."
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  platform/postgres-test:latest \
  psql "host=postgres.company.com dbname=test gssencmode=require" -c "SELECT version()"
```

### Available Test Containers

| Container | Dockerfile | Purpose | Tools Included |
|-----------|-----------|---------|----------------|
| `platform/sqlcmd-test` | `Dockerfile.sqlcmd-test` | SQL Server testing | sqlcmd, bcp, msodbcsql18 |
| `platform/kerberos-test` | `Dockerfile.test-image` | Python DB testing | pyodbc, psycopg2, python3 |
| `platform/postgres-test` | (Future) | PostgreSQL testing | psql, krb5 |

---

## Rollback Plan

If you encounter issues with the minimal sidecar, you can quickly revert to the legacy image.

### Quick Rollback (docker-compose)

```bash
# Stop minimal sidecar
docker compose down kerberos-sidecar

# Edit docker-compose.yml
# Change: image: platform/kerberos-sidecar:minimal
# Back to: image: platform/kerberos-sidecar:legacy

# Restart with legacy image
docker compose up -d kerberos-sidecar

# Verify
docker logs kerberos-sidecar
```

### Rollback in Kubernetes

```bash
# Rollback deployment to previous version
kubectl rollout undo deployment/kerberos-sidecar

# Or specify specific revision
kubectl rollout undo deployment/kerberos-sidecar --to-revision=2

# Verify rollback
kubectl rollout status deployment/kerberos-sidecar
kubectl get pods | grep kerberos-sidecar
```

### When to Rollback

Rollback if you experience:
- ❌ Sidecar health checks failing
- ❌ Tickets not being acquired or renewed
- ❌ Missing dependencies in ticket manager script
- ❌ Corporate policies require specific packages

### After Rollback

If you rolled back:
1. **Document the issue**: What failed? Error messages?
2. **Check compatibility**: Does your environment need legacy features?
3. **File an issue**: Report the problem to platform team
4. **Test in staging**: Try minimal sidecar in non-prod first

---

## Troubleshooting Common Issues

### Problem 1: "Command not found: sqlcmd"

**Symptom**:
```bash
docker exec kerberos-sidecar sqlcmd
# Error: sqlcmd: command not found
```

**Root Cause**: The minimal sidecar does NOT include sqlcmd (by design).

**Solution**: Use the sqlcmd test container instead.

```bash
# Correct approach:
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  platform/sqlcmd-test:latest \
  sqlcmd -S server.company.com -E -Q "SELECT 1"
```

---

### Problem 2: "No such image: platform/kerberos-sidecar:minimal"

**Symptom**:
```bash
docker compose up
# Error: pull access denied for platform/kerberos-sidecar, repository does not exist
```

**Root Cause**: Minimal image not built yet.

**Solution**:
```bash
# Build minimal image
cd kerberos-sidecar
make build-minimal

# Verify
docker images | grep kerberos-sidecar
```

---

### Problem 3: Sidecar Health Check Failing

**Symptom**:
```bash
docker ps
# STATUS: unhealthy
```

**Root Cause**: Tickets not being acquired or renewed.

**Diagnosis**:
```bash
# Check logs
docker logs kerberos-sidecar

# Common issues:
# - Invalid KRB_PRINCIPAL
# - Wrong password/keytab
# - Network issues to KDC
# - krb5.conf misconfigured

# Test health check manually
docker exec kerberos-sidecar klist -s
echo $?  # Should be 0

# See detailed ticket info
docker exec kerberos-sidecar klist
```

**Solution**:
```bash
# Verify environment variables
docker exec kerberos-sidecar env | grep KRB

# Check krb5.conf
docker exec kerberos-sidecar cat /etc/krb5.conf

# Test kinit manually
docker exec -it kerberos-sidecar /bin/bash
kinit user@COMPANY.COM  # Enter password when prompted
klist  # Should show valid ticket
```

---

### Problem 4: Test Container Can't Read Tickets

**Symptom**:
```bash
docker run --rm platform/sqlcmd-test:latest sqlcmd -E
# Error: No credentials cache found
```

**Root Cause**: Ticket cache volume not mounted.

**Solution**:
```bash
# Ensure you mount the volume
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \        # ← THIS IS REQUIRED
  -e KRB5CCNAME=/krb5/cache/krb5cc \        # ← AND THIS
  platform/sqlcmd-test:latest \
  sqlcmd -E

# Verify tickets are accessible
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  klist  # Should show tickets from sidecar
```

---

### Problem 5: "Missing dependency: libstdc++"

**Symptom**:
```bash
docker logs kerberos-sidecar
# Error: libstdc++.so.6: cannot open shared object file
```

**Root Cause**: Legacy scripts/tools expecting libraries not in minimal image.

**Solution**: This shouldn't happen with core Kerberos tools, but if it does:

```bash
# Temporary workaround: Use legacy image
docker compose down
# Edit docker-compose.yml → image: platform/kerberos-sidecar:legacy
docker compose up -d

# Long-term fix: Update Dockerfile.minimal to include missing library
# File an issue with details about what's missing
```

---

### Problem 6: Corporate Artifactory Authentication

**Symptom**:
```bash
make build-minimal
# Error: unauthorized: authentication required
```

**Root Cause**: Not logged into corporate registry.

**Solution**:
```bash
# Login to Artifactory
docker login artifactory.company.com
# Username: <your-corp-username>
# Password: <your-api-token>

# Verify .env has correct IMAGE_ALPINE
cat .env | grep IMAGE_ALPINE
# Should show: IMAGE_ALPINE=artifactory.company.com/docker-remote/alpine:3.19

# Build with corporate base
make build-minimal
```

---

### Problem 7: Performance - Tickets Not Renewing

**Symptom**: Tickets expire and are not renewed.

**Diagnosis**:
```bash
# Check renewal interval
docker exec kerberos-sidecar env | grep RENEWAL_INTERVAL

# Watch logs for renewal messages
docker logs -f kerberos-sidecar

# Expected every RENEWAL_INTERVAL seconds:
# ✓ Renewing ticket for user@COMPANY.COM
# ✓ Ticket renewed successfully
```

**Solution**:
```bash
# Adjust renewal interval (default: 3600 seconds)
# Edit docker-compose.yml:
environment:
  - RENEWAL_INTERVAL=1800  # Renew every 30 minutes

# Restart
docker compose restart kerberos-sidecar
```

---

## Validation Checklist

Use this checklist to verify successful migration:

### Pre-Migration Checklist

- [ ] Backed up current `docker-compose.yml`
- [ ] Verified disk space available (500+ MB)
- [ ] Confirmed access to image registry (if using Artifactory)
- [ ] Documented current image size: `docker images | grep kerberos-sidecar`
- [ ] Tested legacy sidecar is working before migration

### Build Validation

- [ ] Minimal image built successfully: `docker images | grep minimal`
- [ ] Image size < 20 MB: `docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep minimal`
- [ ] Package count < 25: `docker run --rm platform/kerberos-sidecar:minimal apk list | wc -l`
- [ ] No build tools present: `docker run --rm platform/kerberos-sidecar:minimal apk info | grep -E 'gcc|g\+\+|musl-dev'` (should be empty)

### Runtime Validation

- [ ] Minimal sidecar starts successfully: `docker ps | grep kerberos-sidecar`
- [ ] Health check passes: `docker inspect --format='{{.State.Health.Status}}' kerberos-sidecar` (should be "healthy")
- [ ] Tickets acquired: `docker exec kerberos-sidecar klist` (shows valid principal)
- [ ] Tickets renew automatically: Check logs after RENEWAL_INTERVAL seconds
- [ ] Shared volume accessible: `docker volume inspect kerberos-cache`

### Test Container Validation

- [ ] sqlcmd-test built: `docker images | grep sqlcmd-test`
- [ ] sqlcmd-test can read tickets: `docker run --rm -v kerberos-cache:/krb5/cache:ro platform/sqlcmd-test:latest klist`
- [ ] SQL Server connection works: Test with `sqlcmd -E` (if SQL Server available)
- [ ] Python test container built (if needed): `docker images | grep kerberos-test`

### Production Readiness

- [ ] Tested in staging environment (not production first!)
- [ ] Documented rollback procedure
- [ ] Updated CI/CD pipelines to build minimal image
- [ ] Communicated migration to team
- [ ] Monitoring/alerting configured for sidecar health

### Post-Migration Validation

- [ ] Confirmed image size reduction: Compare legacy vs minimal
- [ ] Verified no connectivity regressions: Test all database connections
- [ ] Checked logs for any errors or warnings
- [ ] Validated ticket renewal working over time (24+ hours)
- [ ] Removed legacy image from production (after successful migration)

---

## Complete Migration Example

Here's a complete end-to-end migration example for a typical deployment:

### Before: Legacy Setup

```yaml
# docker-compose.yml (Legacy)
version: '3.8'

services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:latest  # 312 MB bloated image
    container_name: kerberos-sidecar
    environment:
      - KRB_PRINCIPAL=svc_airflow@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=${KRB_PASSWORD}
      - RENEWAL_INTERVAL=3600
    volumes:
      - kerberos-cache:/krb5/cache
      - ./krb5.conf:/krb5/conf/krb5.conf:ro
    networks:
      - airflow-network

  airflow-worker:
    image: apache/airflow:2.7.0
    depends_on:
      - kerberos-sidecar
    environment:
      - KRB5CCNAME=/krb5/cache/krb5cc
    volumes:
      - kerberos-cache:/krb5/cache:ro
      - ./dags:/opt/airflow/dags
    networks:
      - airflow-network

volumes:
  kerberos-cache:

networks:
  airflow-network:
```

**Testing SQL Server (Legacy - using bloated sidecar):**
```bash
# sqlcmd was baked into the 312 MB sidecar
docker exec kerberos-sidecar sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"
```

### After: Minimal Setup

```yaml
# docker-compose.yml (Minimal)
version: '3.8'

services:
  kerberos-sidecar:
    image: platform/kerberos-sidecar:minimal  # 16 MB minimal image
    container_name: kerberos-sidecar
    environment:
      - KRB_PRINCIPAL=svc_airflow@COMPANY.COM
      - USE_PASSWORD=true
      - KRB_PASSWORD=${KRB_PASSWORD}
      - RENEWAL_INTERVAL=3600
    volumes:
      - kerberos-cache:/krb5/cache
      - ./krb5.conf:/krb5/conf/krb5.conf:ro
    networks:
      - airflow-network
    healthcheck:
      test: ["CMD", "klist", "-s"]
      interval: 30s
      timeout: 10s
      retries: 3

  airflow-worker:
    image: apache/airflow:2.7.0
    depends_on:
      kerberos-sidecar:
        condition: service_healthy
    environment:
      - KRB5CCNAME=/krb5/cache/krb5cc
    volumes:
      - kerberos-cache:/krb5/cache:ro
      - ./dags:/opt/airflow/dags
    networks:
      - airflow-network

volumes:
  kerberos-cache:

networks:
  airflow-network:
```

**Testing SQL Server (Minimal - using test container):**
```bash
# Build test container once
make build-sqlcmd-test

# Use test container for connectivity testing
docker run --rm \
  --network airflow-network \
  -v kerberos-cache:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  sqlcmd -S sqlserver.company.com -E -Q "SELECT @@VERSION"
```

### Migration Commands (Copy-Paste Ready)

```bash
#!/bin/bash
# migrate-to-minimal.sh
# Complete migration script - copy and customize for your environment

set -euo pipefail

echo "=== Kerberos Sidecar Migration: Legacy → Minimal ==="
echo ""

# Step 1: Backup current setup
echo "Step 1: Backing up current configuration..."
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d-%H%M%S)
echo "✓ Backup created"
echo ""

# Step 2: Build minimal sidecar
echo "Step 2: Building minimal sidecar image..."
cd kerberos-sidecar
make build-minimal
echo "✓ Minimal image built"
echo ""

# Step 3: Verify image size
echo "Step 3: Verifying image size..."
IMAGE_SIZE=$(docker images platform/kerberos-sidecar:minimal --format "{{.Size}}")
echo "Minimal image size: $IMAGE_SIZE"
if [[ "$IMAGE_SIZE" =~ "MB" ]] && [[ "${IMAGE_SIZE%MB*}" -lt 20 ]]; then
    echo "✓ Image size acceptable (< 20 MB)"
else
    echo "⚠ Warning: Image size larger than expected"
fi
echo ""

# Step 4: Build test containers
echo "Step 4: Building test containers..."
make build-sqlcmd-test
make build-test-image
echo "✓ Test containers built"
echo ""

# Step 5: Stop legacy sidecar
echo "Step 5: Stopping legacy sidecar..."
cd ..
docker compose down kerberos-sidecar
echo "✓ Legacy sidecar stopped"
echo ""

# Step 6: Update docker-compose.yml
echo "Step 6: Updating docker-compose.yml..."
sed -i 's|platform/kerberos-sidecar:latest|platform/kerberos-sidecar:minimal|g' docker-compose.yml
echo "✓ Configuration updated"
echo ""

# Step 7: Start minimal sidecar
echo "Step 7: Starting minimal sidecar..."
docker compose up -d kerberos-sidecar
sleep 5
echo "✓ Minimal sidecar started"
echo ""

# Step 8: Verify health
echo "Step 8: Verifying sidecar health..."
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' kerberos-sidecar)
if [ "$HEALTH_STATUS" = "healthy" ]; then
    echo "✓ Sidecar is healthy"
else
    echo "⚠ Sidecar health: $HEALTH_STATUS (may need time to initialize)"
fi
echo ""

# Step 9: Verify tickets
echo "Step 9: Verifying ticket acquisition..."
sleep 10  # Give time for ticket acquisition
docker exec kerberos-sidecar klist
echo "✓ Tickets acquired"
echo ""

# Step 10: Test connectivity (if SQL Server available)
echo "Step 10: Testing SQL Server connectivity (optional)..."
read -p "Enter SQL Server hostname to test (or press Enter to skip): " SQL_SERVER
if [ -n "$SQL_SERVER" ]; then
    docker run --rm \
      --network $(docker network ls --filter "name=airflow" --format "{{.Name}}" | head -1) \
      -v kerberos-cache:/krb5/cache:ro \
      -v $(pwd)/kerberos-sidecar/krb5.conf:/etc/krb5.conf:ro \
      -e KRB5CCNAME=/krb5/cache/krb5cc \
      platform/sqlcmd-test:latest \
      sqlcmd -S "$SQL_SERVER" -E -Q "SELECT @@VERSION"
    echo "✓ SQL Server connectivity verified"
else
    echo "⊘ Skipped SQL Server test"
fi
echo ""

echo "=== Migration Complete ==="
echo ""
echo "Summary:"
echo "  - Legacy image: 312 MB → Minimal image: ~16 MB"
echo "  - Sidecar health: $HEALTH_STATUS"
echo "  - Backup saved: docker-compose.yml.backup.*"
echo ""
echo "Next steps:"
echo "  1. Verify Airflow connections work with minimal sidecar"
echo "  2. Monitor logs for 24 hours: docker logs -f kerberos-sidecar"
echo "  3. Update CI/CD to use :minimal tag"
echo "  4. Remove legacy image after successful validation"
echo ""
echo "Rollback (if needed):"
echo "  docker compose down"
echo "  mv docker-compose.yml.backup.* docker-compose.yml"
echo "  docker compose up -d"
```

## Additional Resources

### Documentation Links

- [Kerberos Sidecar README](./README.md) - Main documentation
- [Sidecar Architecture Comparison](../SIDECAR-ARCHITECTURE-COMPARISON.md) - Technical deep dive
- [Test Container Dockerfiles](./Dockerfile.sqlcmd-test) - Reference implementations

### Example Configurations

See `docker-compose.yml` and test scripts in the repository for working examples.

### Quick Reference Commands

```bash
# Build minimal sidecar
cd kerberos-sidecar && make build-minimal

# Build test containers
make build-sqlcmd-test
make build-test-image

# Check image sizes
docker images | grep kerberos

# Verify sidecar health
docker inspect --format='{{.State.Health.Status}}' kerberos-sidecar

# Check tickets
docker exec kerberos-sidecar klist

# Test SQL Server connection
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  sqlcmd -S server.company.com -E -Q "SELECT 1"

# Test PostgreSQL connection
docker run --rm \
  -v kerberos-cache:/krb5/cache:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/postgres-test:latest \
  psql "host=postgres.company.com dbname=mydb gssencmode=require" -c "SELECT version()"
```

### Getting Help

If you encounter issues:

1. **Check logs**: `docker logs kerberos-sidecar`
2. **Verify configuration**: `docker exec kerberos-sidecar env`
3. **Test manually**: `docker exec -it kerberos-sidecar /bin/bash`
4. **File an issue**: Include logs, configuration, and error messages

---

## Summary

**Migration Overview**:
1. Build minimal sidecar (16 MB vs 312 MB)
2. Update docker-compose.yml to use `:minimal` tag
3. Move connectivity testing to separate test containers
4. Validate tickets are acquired and renewed
5. Test database connections using test containers

**Key Benefits**:
- 19x smaller image size
- Reduced security attack surface
- Aligned with corporate best practices
- Separation of concerns (ticket management vs connectivity testing)

**Remember**: The minimal sidecar does ONE thing well - manages Kerberos tickets. Use separate test containers for connectivity validation.

**Rollback**: If needed, revert to `:legacy` tag in docker-compose.yml.

Good luck with your migration!
