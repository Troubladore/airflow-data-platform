# OpenMetadata Service - Design Decisions

## Overview

Standalone OpenMetadata metadata catalog service as part of the composable platform architecture. This document records key design decisions and deviations from the official OpenMetadata deployment.

## Version

**OpenMetadata 1.10.1** (October 2025)
- Server: `docker.getcollate.io/openmetadata/server:1.10.1`
- Elasticsearch: `docker.elastic.co/elasticsearch/elasticsearch:8.11.4`

## Architecture Decisions

### 1. Standalone Service Pattern

**Decision:** OpenMetadata is a standalone composable service, not embedded in platform-bootstrap.

**Rationale:**
- Follows Pagila pattern (independent services)
- Can be used without platform-bootstrap
- Clear ownership and lifecycle management
- Optional (toggle via platform-bootstrap/.env)

**Structure:**
```
openmetadata/
├── docker-compose.yml   # Self-contained service definition
├── setup.sh             # Progressive validation (6 steps)
├── Makefile             # make start/stop/status/migrate
├── .env                 # Service-specific configuration
└── CLAUDE.md            # This file
```

### 2. External PostgreSQL (platform-infrastructure)

**Decision:** Use shared platform-postgres from platform-infrastructure, not bundled PostgreSQL.

**Official Setup:**
```yaml
postgresql:
  image: docker.getcollate.io/openmetadata/postgresql:1.10.1
  # Bundled with OpenMetadata
```

**Our Setup:**
```yaml
# No postgresql service here
# References: platform-postgres via platform_network
```

**Rationale:**
- platform-postgres is SHARED foundation (Airflow + OpenMetadata + future services)
- Avoids nesting shared resources under "openmetadata" Docker project
- Clear separation: infrastructure vs applications
- Airflow can use platform-postgres without OpenMetadata running

**Trade-off:**
- ✅ Better architecture (shared resources in right place)
- ✅ Single PostgreSQL for all platform OLTP needs
- ⚠️ Dependency: platform-infrastructure must start first
- ⚠️ Setup script validates this prerequisite

### 3. Network Configuration

**Decision:** Use external `platform_network` instead of internal `app_net`.

**Official Setup:**
```yaml
networks:
  app_net:
    driver: bridge
```

**Our Setup:**
```yaml
networks:
  platform-net:
    name: platform_network
    external: true  # Created by platform-infrastructure
```

**Rationale:**
- All platform services share platform_network
- Enables service-to-service communication (OpenMetadata ↔ Kerberos ↔ Airflow)
- Consistent with composable architecture
- Services are peers, not isolated silos

### 4. No Ingestion Container

**Decision:** Exclude the official `ingestion` container (Airflow-based connector).

**Official Setup:**
```yaml
ingestion:
  image: docker.getcollate.io/openmetadata/ingestion:1.10.1
  # Runs Airflow LocalExecutor for metadata ingestion
```

**Our Setup:**
```yaml
# No ingestion service
# Use Astronomer Airflow DAGs instead
```

**Rationale:**
- We use **Astronomer** for orchestration (not bundled Airflow)
- Ingestion runs as Astronomer DAGs (everything-as-code pattern)
- Avoids duplicate Airflow instances
- See: airflow-data-platform-examples/openmetadata-ingestion/

**Configuration Impact:**
```yaml
# These are set but not actively used without ingestion container:
PIPELINE_SERVICE_CLIENT_ENABLED: true
# PIPELINE_SERVICE_CLIENT_ENDPOINT: http://ingestion:8080  # Commented - no ingestion container
```

### 5. Database Migration Strategy

**Decision:** Migration runs as one-shot container before server starts.

**Implementation:**
```yaml
openmetadata-migrate:
  image: docker.getcollate.io/openmetadata/server:1.10.1
  command: "./bootstrap/openmetadata-ops.sh migrate"
  restart: "no"  # One-shot - exits after completion
  depends_on:
    openmetadata-elasticsearch:
      condition: service_healthy

openmetadata-server:
  depends_on:
    openmetadata-migrate:
      condition: service_completed_successfully  # CRITICAL
```

**Rationale:**
- Server needs schema tables to exist before starting
- Migrations must complete successfully before server starts
- Idempotent - safe to run multiple times
- setup.sh runs this automatically

**Commands:**
- Version 1.2.0 used: `./bootstrap/bootstrap_storage.sh migrate-all` (old)
- Version 1.10.1 uses: `./bootstrap/openmetadata-ops.sh migrate` (current)

### 6. Health Check Configuration

**Decision:** Use port 8586 admin endpoint with wget, not port 8585 API endpoint.

**Official 1.10.1:**
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://localhost:8586/healthcheck"]
```

**Our Initial (Wrong):**
```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:8585/api/v1/health || exit 1"]
```

**Current (Fixed):**
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://localhost:8586/healthcheck"]
  start_period: 60s
```

**Rationale:**
- Admin port (8586) is specifically for health checks
- API port (8585) is for actual metadata operations
- `/healthcheck` endpoint is reliable across versions
- `/api/v1/health` returns 404 in some configurations
- `wget` is included in container, reliable tool

**Lesson Learned:**
- Don't assume health endpoints - check official docs!
- Version matters - 1.2.0 vs 1.10.1 have different endpoints

### 7. Centralized Secrets (platform-bootstrap/.env)

**Decision:** Passwords managed in platform-bootstrap/.env (single source of truth), synchronized to service .env files.

**Problem:**
- platform-infrastructure creates `openmetadata_user` with password
- openmetadata needs same password to connect
- Two different .env files = two different passwords = auth failure

**Solution:**
```
platform-bootstrap/.env (MASTER):
  OPENMETADATA_DB_USER=openmetadata_user
  OPENMETADATA_DB_PASSWORD=openmetadata_password

openmetadata/.env (SYNCHRONIZED by wizard):
  DB_USER=openmetadata_user
  DB_USER_PASSWORD=openmetadata_password
```

**Rationale:**
- Acts as lightweight secrets manager
- Single source of truth for all credentials
- Setup wizard synchronizes passwords
- Each service uses its expected variable names
- Clear master/copy relationship
- Future: Replace with proper secrets manager (Vault, AWS Secrets Manager)

**Trade-off:**
- ⚠️ Passwords duplicated in two files
- ✅ But: wizard keeps them in sync
- ✅ Clear which is master (platform-bootstrap)
- ✅ Services use their native variable names

### 8. Environment Variable Completeness

**Decision:** Include ALL environment variables from official config, even if disabled.

**Approach:**
```yaml
# Active variables
AUTHENTICATION_PROVIDER: basic

# Disabled features (commented with reason)
# OIDC Authentication (Disabled - using basic auth for local dev)
# OIDC_CLIENT_ID: ""
# OIDC_CLIENT_SECRET: ""
# ...

# Security features (disabled for local dev - no HTTPS)
WEB_CONF_HSTS_ENABLED: false
WEB_CONF_FRAME_OPTION_ENABLED: false
```

**Rationale:**
- Configuration parity with official deployment
- Easy to enable features later (just uncomment)
- Documents what's available
- Prevents unexpected behaviors from missing defaults
- Clear reasons for disabled features

**Categories Included:**
1. ✅ Server configuration (ports, logging)
2. ✅ Database configuration (PostgreSQL connection)
3. ✅ Elasticsearch configuration (full settings)
4. ✅ Authentication (Basic, OIDC, SAML, LDAP - latter 3 disabled)
5. ✅ Authorization (admin principals, domains)
6. ✅ JWT configuration (keys, issuer)
7. ✅ Pipeline/Airflow integration
8. ✅ Secrets manager (using db, not AWS/Azure)
9. ✅ Email notifications (disabled for local)
10. ✅ Event monitoring (prometheus)
11. ✅ Web security headers (disabled - no HTTPS locally)
12. ✅ Performance tuning (heap size)

### 9. PostgreSQL Connection Parameters

**Decision:** Use component-based DB config (DB_SCHEME, DB_HOST, etc.) not just DB_URL.

**Why Both:**
```yaml
# Component-based (OpenMetadata 1.10.x builds URL from these)
DB_DRIVER_CLASS: org.postgresql.Driver
DB_SCHEME: postgresql
DB_HOST: platform-postgres
DB_PORT: 5432
DB_PARAMS: allowPublicKeyRetrieval=true&useSSL=false&serverTimezone=UTC
OM_DATABASE: openmetadata_db
DB_USER: openmetadata_user
# DB_USER_PASSWORD from .env

# Note: DB_URL not used in 1.10.x (uses components above)
# Older versions used: jdbc:postgresql://platform-postgres:5432/openmetadata_db
```

**Lesson Learned:**
- OpenMetadata 1.10.x ignores DB_URL if component vars are set
- Missing DB_SCHEME caused it to default to MySQL!
- Always check official config for required variables

### 10. Setup Script Progressive Validation

**Decision:** 6-step progressive validation in setup.sh.

**Steps:**
1. Check prerequisites (Docker, curl)
2. Configure .env (generate passwords, preserve existing)
3. Start services (validate infrastructure, handle existing containers)
4. Run migrations (create schema tables)
5. Validate health (Elasticsearch → OpenMetadata with real-time progress)
6. Summary (next steps, service info)

**Data Preservation:**
- Containers: Asked before recreation (restart vs recreate vs skip)
- Volumes: ALWAYS preserved (explicit warning if deletion chosen)
- .env: Preserved in auto mode, asked in interactive mode

**User Experience:**
- Real-time progress with countdown timers
- Clear status messages (starting → healthy)
- Helpful troubleshooting on failures
- Data safety emphasized

## Deviations from Official Setup

| Aspect | Official 1.10.1 | Our Implementation | Reason |
|--------|-----------------|-------------------|---------|
| PostgreSQL | Bundled postgresql service | External platform-postgres | Shared infrastructure pattern |
| Network | app_net (isolated) | platform_network (shared) | Service integration |
| Ingestion | Included Airflow container | Excluded | Use Astronomer instead |
| Secrets | Can use AWS/Azure | Using db (local .env) | Local development simplicity |
| Auth | Production-ready OIDC/SAML | Basic auth only | Local dev, commented others |
| HTTPS | Optional TLS | Disabled (no HSTS/CSP) | Local dev over HTTP |

## Troubleshooting Guide

### OpenMetadata Won't Start

**Check migration completed:**
```bash
docker logs openmetadata-migrate
# Should see: "Migration completed successfully"
```

**Check database tables exist:**
```bash
docker exec platform-postgres psql -U platform_admin -d openmetadata_db -c "\dt" | grep openmetadata_settings
# Should show openmetadata_settings table
```

**Check health endpoint:**
```bash
curl http://localhost:8586/healthcheck
# Should return: {"OpenMetadataServerHealthCheck":{"healthy":true}}
```

### Password Authentication Failed

**Symptom:** Logs show "password authentication failed for user openmetadata_user"

**Cause:** Passwords out of sync between platform-bootstrap/.env and openmetadata/.env

**Fix:**
```bash
# Ensure passwords match:
grep OPENMETADATA_DB_PASSWORD ../platform-bootstrap/.env
grep DB_USER_PASSWORD .env
# Should be the same value!

# Recreate database with correct password:
cd ../platform-infrastructure
docker compose down -v  # Deletes database
docker compose up -d    # Recreates with password from .env
```

### Migration Fails

**Check platform-postgres is running:**
```bash
docker ps | grep platform-postgres
# Must be healthy before migration runs
```

**Check Elasticsearch is healthy:**
```bash
docker inspect openmetadata-elasticsearch --format='{{.State.Health.Status}}'
# Must be healthy (green or yellow cluster status)
```

**Manual migration:**
```bash
docker compose up openmetadata-migrate
# Watch for errors in schema creation
```

### Health Check Stays "Starting"

**This is normal for 1-2 minutes on first run!**

OpenMetadata is a Java application that:
- Initializes Spring Boot
- Connects to PostgreSQL and Elasticsearch
- Loads metadata schemas
- Starts web server
- Registers REST API endpoints

**If stuck for 5+ minutes:**
```bash
# Check logs for errors
docker logs openmetadata-server | grep ERROR

# Check if UI is accessible (sometimes healthcheck lags)
curl -s http://localhost:8585 | grep title
# Should show: <title>OpenMetadata</title>

# Check admin healthcheck specifically
curl http://localhost:8586/healthcheck
```

## Future Enhancements

### When to Enable OIDC/SAML

Uncomment OIDC/SAML configuration when:
- Deploying to shared/production environment
- Need corporate SSO integration
- Want centralized user management

See commented sections in docker-compose.yml.

### When to Add Ingestion Container

Consider adding the official ingestion service if:
- You need UI-based connector configuration
- You don't want to use Astronomer for ingestion
- You need the bundled Airflow instance

Official ingestion service can coexist with Astronomer.

### Secrets Manager Integration

Replace `SECRET_MANAGER: db` with AWS/Azure when:
- Moving to production
- Need encrypted secrets storage
- Compliance requirements

Update:
```yaml
SECRET_MANAGER: aws  # or azure
OM_SM_REGION: us-east-1
OM_SM_ACCESS_KEY_ID: ${AWS_ACCESS_KEY}
OM_SM_ACCESS_KEY: ${AWS_SECRET_KEY}
```

## Testing

**Validate setup:**
```bash
make setup    # Full wizard with validations
make migrate  # Run migrations only
make start    # Start services
make status   # Check health
```

**Test health:**
```bash
# Admin healthcheck (used by Docker)
curl http://localhost:8586/healthcheck

# UI access
open http://localhost:8585

# API access
curl http://localhost:8585/api/v1/tables
```

## Configuration Reference

**platform-bootstrap/.env (Master Secrets):**
```bash
# These are synchronized to openmetadata/.env by wizard
OPENMETADATA_DB_USER=openmetadata_user
OPENMETADATA_DB_PASSWORD=<generated-or-set>
OPENMETADATA_PORT=8585
OPENMETADATA_CLUSTER_NAME=local-dev
```

**openmetadata/.env (Service-Specific):**
```bash
# Synchronized from platform-bootstrap/.env
DB_USER=openmetadata_user
DB_USER_PASSWORD=<same-as-bootstrap>

# Service-specific (not in platform-bootstrap)
OPENMETADATA_PORT=8585
OPENMETADATA_CLUSTER_NAME=local-dev
```

## Version Upgrade Notes

### Upgrading from 1.2.x to 1.10.x

**Critical Changes:**
1. Migration command changed:
   - Old: `./bootstrap/bootstrap_storage.sh migrate-all`
   - New: `./bootstrap/openmetadata-ops.sh migrate`

2. Health endpoint changed:
   - Old: Port 8585, `/api/v1/health` (unreliable)
   - New: Port 8586, `/healthcheck` (reliable)

3. Database connection:
   - Old: Could use just DB_URL
   - New: MUST use DB_SCHEME, DB_HOST, DB_PORT, OM_DATABASE
   - Missing DB_SCHEME causes fallback to MySQL!

4. Environment variables:
   - 1.2.x: ~40 variables
   - 1.10.x: 100+ variables
   - Many new auth/security/monitoring options

**Migration Path:**
1. Stop services: `make stop`
2. Update image versions in docker-compose.yml
3. Run new migrations: `make migrate`
4. Start with new config: `make start`
5. Verify health: `make status`

### Why We Stayed on 1.10.1 (not latest)

As of October 2025, 1.10.1 is recent and stable. We chose this version because:
- Latest stable release at time of implementation
- Well-documented
- Compatible with PostgreSQL 17.5
- Elasticsearch 8.11.4 compatible

**Future upgrades:** Check OpenMetadata release notes for breaking changes.

## Lessons Learned

### 1. Version Matters - A Lot

**Problem:** We started with 1.2.0, had mysterious failures.
**Root Cause:** 8 versions behind, missing critical config changes.
**Lesson:** Always use recent stable version, check release notes for breaking changes.

### 2. Health Endpoints Are Not Standard

**Problem:** Assumed `/api/v1/health` would work (common pattern).
**Reality:** OpenMetadata uses `/healthcheck` on admin port.
**Lesson:** Always check official docker-compose for exact healthcheck command.

### 3. Password Coordination is Hard

**Problem:** Shared PostgreSQL means password coordination across services.
**Solution:** platform-bootstrap/.env as single source of truth, wizard synchronizes.
**Lesson:** Centralized secrets management is essential for composable architecture.

### 4. Migration Must Run First

**Problem:** Server crashed on fresh database (no tables).
**Reality:** OpenMetadata needs schema initialized before server starts.
**Lesson:** Always check if application needs migration/initialization step.

### 5. Environment Variables - All or Nothing

**Problem:** Missing obscure env vars caused unexpected defaults (MySQL instead of PostgreSQL!).
**Solution:** Include ALL official variables with documentation.
**Lesson:** Don't cherry-pick env vars - include everything, document disabled features.

## Dependencies

**Hard Dependencies (Required):**
- platform-infrastructure (provides platform-postgres, platform_network)
- Elasticsearch (for search/indexing)

**Soft Dependencies (Optional):**
- Astronomer Airflow (for DAG-based ingestion)
- Pagila (for testing metadata catalog)

**Not Used:**
- Ingestion container (we use Astronomer)
- AWS/Azure secrets manager (use db for local dev)
- SMTP server (email disabled for local)
- OIDC/SAML providers (basic auth for local)

## Contact & Support

**Vendor Docs:** https://docs.open-metadata.org/latest
**Official Releases:** https://github.com/open-metadata/OpenMetadata/releases
**Our Platform Docs:** See platform-bootstrap/README.md

**For Issues:**
1. Check this file for troubleshooting
2. Check setup script validations: `./setup.sh`
3. Check official docs for version-specific changes
4. Compare with official docker-compose for your version

---

**Last Updated:** 2025-10-21
**OpenMetadata Version:** 1.10.1
**Maintained By:** Platform team via Claude Code
