# OpenMetadata Integration - Decisions Summary

**Date:** 2025-01-16
**Status:** Ready for Implementation

---

## Architectural Revisions (2025-01-16 Update)

**Critical simplifications based on team feedback:**

1. **No separate ingestion container** - Use Astronomer for ingestion DAGs
2. **Shared PostgreSQL** - Platform services share one PostgreSQL instance
3. **OLTP/OLAP separation** - Platform Postgres separate from warehouse Postgres
4. **Everything as code** - Skip manual UI, go straight to programmatic ingestion

**Result:** 3 services instead of 4, matches production patterns, aligns with team culture.

---

## Decisions Made

### 1. Deployment Model: **ALWAYS-ON**

**Decision:** OpenMetadata runs as a standard platform service, like the Kerberos sidecar.

**What this means:**
- `make platform-start` starts both Kerberos AND OpenMetadata
- OpenMetadata is available whenever the platform is running
- No separate "turn on metadata" step
- Consistent with platform service pattern

**Implementation impact:**
- Update `Makefile` to make `platform-start` launch both compose files
- Add `openmetadata-only` target for rare cases where only OM is needed
- Update setup wizard to mention OpenMetadata starts automatically

### 2. Corporate Environment: **ARTIFACTORY MIRRORS PROVIDED**

**Decision:** IT will provide Artifactory mirrors. Image paths stored in `.env`.

**Configuration pattern:**
```bash
# In .env (not committed to git)
IMAGE_OPENMETADATA_SERVER=artifactory.company.com/docker-remote/openmetadata/server:1.2.0
IMAGE_OPENMETADATA_INGESTION=artifactory.company.com/docker-remote/openmetadata/ingestion:1.2.0
IMAGE_ELASTICSEARCH=artifactory.company.com/docker-remote/elasticsearch/elasticsearch:8.10.2
IMAGE_POSTGRES=artifactory.company.com/docker-remote/library/postgres:15
```

**What this means:**
- Same pattern as existing Astronomer images
- Corporate setup person updates `.env` once
- Team members clone fork with pre-configured paths
- Requires `docker login artifactory.company.com` (standard practice)

**Implementation impact:**
- `platform-config.yaml` configuration managed by setup wizard
- Documentation includes corporate configuration section
- Setup wizard prompts for Artifactory paths if in corporate mode

### 3. Team Collaboration: **DUAL MODE**

**Decision:** Single-user locally, shared instance above dev.

**Local Development (Single-User):**
- Each developer runs OpenMetadata on their workstation
- Basic authentication (admin/admin)
- No team coordination needed
- Fast iteration, no network dependencies
- Perfect for learning and experimentation

**INT/QA/PROD (Shared Instance):**
- Centralized OpenMetadata instance per environment
- Shared metadata catalog across team
- LDAP/SSO integration (future)
- Managed by platform/DevOps team
- Single source of truth for metadata

**Migration path:**
- Start: Local instance, prove value
- Mature: Export/import metadata to shared instance
- Long-term: Point local ingestion to shared catalog

**Implementation impact:**
- Phase 1-3: Focus on local single-user setup
- Phase 4+: Add shared instance deployment docs
- No premature complexity for team collaboration

### 4. Integration Depth: **INCREMENTAL**

**Decision:** Build support incrementally. Don't front-load complexity.

**Phase 1-2: Core Functionality**
- Get OpenMetadata running
- Pagila schema discovery (PostgreSQL)
- SQL Server via Kerberos
- **Goal:** Prove basic value

**Phase 3: Airflow Integration**
- Pipeline metadata extraction
- Basic lineage tracking
- **Goal:** Prove lineage value

**Phase 4+: Deeper Integration**
- Cookiecutter template patterns (if valuable)
- Standardized lineage operators (if adopted)
- Team best practices (if proven)
- **Goal:** Standardize what works

**Rationale:**
- Don't assume we know what developers will find valuable
- Let usage patterns emerge organically
- Document patterns, don't mandate them yet
- Avoid premature optimization

**Implementation impact:**
- Documentation shows lineage patterns as **examples**
- Cookiecutter templates remain simple for now
- Add lineage support **after** teams request it
- Phase 4 is flexible based on feedback

### 5. Scope: **FOCUSED**

**In Scope (Phases 1-3):**
- ✅ PostgreSQL (pagila for examples)
- ✅ SQL Server with Kerberos (corporate data)
- ✅ Airflow pipeline metadata and lineage

**Out of Scope (initially):**
- ❌ Cloud data sources (S3, BigQuery, Snowflake)
- ❌ dbt integration
- ❌ Additional databases beyond PostgreSQL and SQL Server

**Approach:**
- Start focused, expand based on real needs
- "Just enough" to be useful
- Avoid feature creep

### 6. Infrastructure Simplification: **3 SERVICES**

**Original plan:** 4 containers (Server, Ingestion, Postgres, Elasticsearch)
**Revised plan:** 3 containers (Server, Shared Postgres, Elasticsearch)

**What was removed:**
- ❌ Separate `openmetadata-ingestion` container (redundant Airflow!)

**Why removed:**
- Infrastructure team won't want bespoke Airflow instances for every tool
- Astronomer is THE orchestrator (don't duplicate it)
- "Everything as code" culture (not manual UI clicking)
- Saves ~2GB RAM

**How ingestion works instead:**
1. **Programmatic (production):** Astronomer DAGs with OpenMetadata Python SDK
2. **Ad-hoc (testing):** Server's built-in connectors via API
3. **Scheduled:** Astronomer DAGs on cron (where all orchestration belongs)

### 7. Database Architecture: **OLTP/OLAP SEPARATION**

**Critical architectural principle:** Separate databases for different workload types.

**Platform PostgreSQL (OLTP):**
- **Location:** `platform-bootstrap/docker-compose.openmetadata.yml`
- **Purpose:** Platform operational data (transactional)
- **Contains:**
  * `openmetadata_db` - Metadata storage
  * `airflow_db` (future) - Airflow metastore
  * Other platform service databases
- **Workload:** Many small, fast transactions
- **Optimization:** Low latency, high availability

**Warehouse PostgreSQL (OLAP):**
- **Location:** Separate instance (NOT in platform-bootstrap!)
- **Purpose:** Data warehouse (analytical)
- **Contains:**
  * Transformed business data
  * Dimensional models
  * Aggregated tables
- **Workload:** Large batch loads, complex analytical queries
- **Optimization:** Query performance, large storage

**Why separate?**
- Performance isolation (analytics don't slow platform)
- Independent scaling (different resource profiles)
- Matches production patterns (RDS vs Redshift, etc.)
- Clear architectural boundaries

**Example flow:**
```
Astronomer DAG:
  1. Extract from pagila (source)
  2. Transform with SQLModel
  3. Load to warehouse-postgres (OLAP) ← Data goes here
  4. Update OpenMetadata via API
  5. Metadata stored in platform-postgres (OLTP) ← Catalog goes here
```

Different workloads, different databases!

---

## Implementation Readiness

### Documentation Status

| Document | Status | Purpose |
|----------|--------|---------|
| openmetadata-integration-design.md | ✅ Complete | Architecture and strategy |
| openmetadata-implementation-spec.md | ✅ Complete | Step-by-step implementation |
| openmetadata-decisions-summary.md | ✅ Complete | This document |
| openmetadata-developer-guide.md | 🔲 Phase 4 | End-user guide |
| openmetadata-admin-guide.md | 🔲 Phase 4 | Operations guide |

### Files Ready to Create

**Phase 1 (Shared Infrastructure + Pagila Ingestion DAG):**
- [ ] `platform-bootstrap/docker-compose.openmetadata.yml` (3 services!)
- [ ] `platform-bootstrap/postgres/init-databases.sh` (multi-database setup)
- [ ] Setup wizard integration for OpenMetadata configuration
- [ ] Updated `platform-bootstrap/Makefile` (platform-start includes OM)
- [ ] `examples/openmetadata-ingestion/dags/ingest_pagila_metadata.py` (DAG!)
- [ ] `examples/openmetadata-ingestion/requirements.txt` (openmetadata-ingestion SDK)

**Phase 2 (SQL Server Kerberos Ingestion DAG):**
- [ ] `examples/openmetadata-ingestion/dags/ingest_sqlserver_metadata.py` (Kerberos DAG!)
- [ ] `platform-bootstrap/diagnostics/test-openmetadata-krb.sh` (diagnostic)

**Phase 3 (Airflow Lineage):**
- [ ] Documentation examples for lineage patterns
- [ ] Example DAG with lineage operators

**Phase 4 (Production):**
- [ ] Health check script
- [ ] Backup/restore scripts (for shared PostgreSQL)
- [ ] Developer guide
- [ ] Admin guide

---

## Next Steps (Agreed)

### Immediate: Begin Phase 1 Implementation

**Goal:** Shared infrastructure + programmatic pagila ingestion (everything as code!)

**Tasks:**
1. Create shared PostgreSQL with init script
2. Create `docker-compose.openmetadata.yml` (3 services)
3. Integrate OpenMetadata configuration in setup wizard
4. Update `Makefile` for always-on deployment
5. Test startup: `make platform-start`
6. Access UI: http://localhost:8585
7. **Create Astronomer project for ingestion DAGs**
8. **Create `ingest_pagila_metadata.py` DAG**
9. **Run DAG to ingest metadata (code-first!)**
10. Verify schema in OpenMetadata UI

**Timeline:** 2-3 days (includes DAG creation)

**Success Criteria:**
- 3 services start without errors (not 4!)
- Shared PostgreSQL has multiple databases
- UI accessible
- **Ingestion DAG runs successfully**
- Pagila tables visible via programmatic ingestion

### Then: Phase 2 (Kerberos SQL Server Ingestion)

**Goal:** Programmatic SQL Server ingestion via Kerberos (DAG-based!)

**Tasks:**
1. Create `ingest_sqlserver_metadata.py` DAG
2. Configure Kerberos in DAG environment
3. Run DAG to ingest SQL Server metadata
4. Create diagnostic script
5. Verify corporate database metadata

**Timeline:** 2-3 days after Phase 1

**Success Criteria:**
- SQL Server ingestion DAG runs successfully
- No username/password (Kerberos only!)
- Corporate database tables cataloged

### Then: Phase 3 (Airflow Lineage)

**Goal:** Capture pipeline metadata and data lineage

**Timeline:** 3-5 days after Phase 2

### Finally: Phase 4 (Production Ready)

**Goal:** Documentation, monitoring, team patterns

**Timeline:** 5-7 days after Phase 3

---

## Key Architectural Insights

### 1. OpenMetadata Enhances Astronomer (Doesn't Replace)

- **Astronomer** = Orchestration (running DAGs, scheduling, monitoring)
- **OpenMetadata** = Metadata catalog (schemas, lineage, discovery)
- **Together** = Complete data platform

Astronomer runs the ingestion DAGs that populate OpenMetadata!

### 2. Shared PostgreSQL Matches Production

**Local development now mirrors production:**
- One PostgreSQL instance with multiple databases
- Platform services share `platform-postgres`
- Warehouse has separate `warehouse-postgres`
- OLTP/OLAP workloads properly separated

**Benefits:**
- Realistic architecture patterns
- Single backup/restore process for platform
- Easy to add new platform services (just add a database)
- Infrastructure team happy (no DB sprawl)

### 3. No Redundant Airflow = Simpler + Cheaper

**Before:** 4 containers including redundant Airflow in ingestion container
**After:** 3 containers, ingestion runs in Astronomer (where it belongs!)

**Savings:**
- ~2GB RAM
- One less service to manage
- No duplicate orchestrator
- Aligns with "Astronomer is THE orchestrator" principle

### 4. Everything as Code Matches Team Culture

**No manual UI clicking:**
- Ingestion configured as code (Python DAGs)
- Version controlled in git
- Code review for changes
- Repeatable and testable

**Example:**
```python
# Ingestion as code!
config = {...}  # All configuration in Python
workflow = Workflow.create(config)
workflow.execute()
```

### 5. OLTP/OLAP Separation is Production-Ready

**Platform PostgreSQL (OLTP):**
- OpenMetadata metadata, Airflow metastore, etc.
- Transactional workloads
- Low latency, many small operations

**Warehouse PostgreSQL (OLAP):**
- Business data, dimensional models
- Analytical workloads
- Query performance, large batch loads

**Key insight:** Same DAG can ETL data to warehouse AND update metadata catalog - different databases!

### 6. Incremental + Code-First = Low Risk

- **Phase 1:** Infrastructure + pagila ingestion DAG (prove DAG pattern)
- **Phase 2:** SQL Server ingestion DAG (prove Kerberos + code)
- **Phase 3:** Lineage integration (prove value)
- **Phase 4:** Documentation (standardize what works)

Each phase validates value before continuing.

---

## Risk Mitigation Updates

Based on decisions, updated risk assessment:

### Risk: Resource Usage

**Status:** Mitigated by always-on decision

- OpenMetadata uses ~6.5GB RAM
- But if it's always-on, developers will allocate resources accordingly
- Clear documentation of minimum requirements
- No surprise "oh, I also need to start metadata service"

### Risk: Corporate Firewall

**Status:** Mitigated by Artifactory decision

- IT providing mirrors = no firewall issues
- Same pattern as existing images
- Configuration in `.env` is standard practice

### Risk: Adoption

**Status:** Mitigated by incremental approach

- Don't mandate lineage patterns yet
- Let value emerge organically
- Prove usefulness before standardizing

### Risk: Maintenance Burden

**Status:** Mitigated by always-on + focused scope

- Always-on = treated as core service (gets attention)
- Focused scope = less surface area to support
- Good documentation = self-service

---

## Success Metrics (Aligned with Decisions)

### Phase 1 Success
- [ ] Services start on first try
- [ ] Pagila metadata visible
- [ ] Developer can find table schema in < 30 seconds

### Phase 2 Success
- [ ] Kerberos diagnostic passes
- [ ] SQL Server connection works without credentials
- [ ] Corporate database metadata harvested

### Phase 3 Success
- [ ] DAG structure visible in OpenMetadata
- [ ] Lineage graph renders correctly
- [ ] At least one team member finds it valuable

### Long-term Success (Post Phase 4)
- Developers use OpenMetadata for schema discovery
- "Where is this data?" questions reduced
- Lineage helps with impact analysis
- Metadata quality improves

---

## Communication Plan

### For Developers

**Message:**
"OpenMetadata now runs automatically with `make platform-start`. It provides schema discovery and data cataloging. Check out http://localhost:8585 after starting the platform."

**When:**
After Phase 1 is complete and tested

**How:**
- Team demo
- Updated README
- Slack announcement

### For Platform Team

**Message:**
"We're integrating OpenMetadata as an always-on platform service. Uses existing Kerberos sidecar pattern. Local instances for dev, shared instances for INT+."

**When:**
Before Phase 1 implementation starts

**How:**
- Architecture review meeting
- Share design documents
- Gather feedback

### For IT/DevOps

**Message:**
"We need Artifactory mirrors for OpenMetadata images (4 images total). Same pattern as Astronomer images. Here are the public image references..."

**When:**
Before Phase 1 (so mirrors are ready)

**How:**
- Email with specific image list
- Reference existing Astronomer mirror setup
- Coordinate on timeline

---

## Questions Resolved

✅ **Deployment scope?** Always-on (like Kerberos sidecar)
✅ **Corporate environment?** Artifactory mirrors provided, paths in `.env`
✅ **Team collaboration?** Dual mode (local for dev, shared for INT+)
✅ **Integration depth?** Incremental (prove value before standardizing)
✅ **Scope?** Focused (PostgreSQL, SQL Server, Airflow)

---

## Ready to Implement!

All architectural decisions made. Documentation complete. Implementation path clear.

**Next concrete action:** Create Phase 1 files and test basic startup.

**Command to execute:**
```bash
cd ~/repos/airflow-data-platform/platform-bootstrap

# Create docker-compose.openmetadata.yml
# Run setup wizard: ./platform setup
# Update Makefile
# Test: make platform-start
```

Let's build it! 🚀
