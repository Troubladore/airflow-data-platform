# Platform Architecture Vision

**Status:** Design Document
**Date:** 2025-10-11
**Purpose:** Define the architectural vision for the Airflow Data Platform as a standardized, reusable foundation for enterprise data engineering teams.

---

## Executive Summary

The Airflow Data Platform provides a **standardized Layer 1 foundation** as a buildable Docker image that teams customize once and reuse across all data engineering projects. This eliminates repetitive corporate configuration (Artifactory paths, Kerberos settings, common dependencies) and enables developers to focus on building datakits (Layer 2) rather than infrastructure setup.

**Key Insight:** Docker's native image caching eliminates the need for local registry services. A single Docker daemon shares images across all compose stacks automatically.

---

## Three-Layer Architecture

### Layer 1: Platform Base (This Repository)
**What:** A buildable Docker image (`layer1-airflow:latest`) extending Astronomer's runtime with:
- Corporate Artifactory image sources pre-configured
- Kerberos client libraries and corporate realm configuration
- SQLModel framework for consistent data modeling
- Common dependencies (pyodbc, sqlalchemy, etc.)
- Security and compliance settings

**Who Configures:** One "setup person" per organization
**Frequency:** Once initially, occasional updates
**Output:** `layer1-airflow:latest` in local Docker cache

### Layer 2: Datakits (Developer Projects)
**What:** Individual data engineering projects (customer-360, product-analytics, etc.) created from cookiecutter template
**Who Builds:** Every developer for each new datakit
**Frequency:** Many times (one per business use case)
**Pattern:** `FROM layer1-airflow:latest` + add DAGs
**Benefit:** Fast builds (just adds application code to pre-built base)

### Layer 3: Warehouse Configuration (Deployment Targets)
**What:** Environment-specific configurations (dev/int/qa/prod)
**Pattern:** Helm charts, Kubernetes manifests, environment variables
**Scope:** Beyond this repository's focus

---

## Mono-Repo Structure

The repository is organized as a mono-repo with clear boundaries between related but independent components:

```
airflow-data-platform/
│
├── layer1-base-image/              # Buildable Layer 1 artifact
│   ├── Dockerfile                  # Extends Astronomer + adds platform
│   ├── requirements.txt            # Common Python dependencies
│   ├── packages.txt                # OS packages (krb5-user, etc.)
│   ├── config/
│   │   └── krb5.conf.example       # Corporate Kerberos configuration
│   ├── Makefile                    # Build commands
│   └── README.md                   # Layer 1 setup instructions
│
├── sqlmodel-framework/             # Python library for data modeling
│   ├── src/sqlmodel_framework/     # Installed into Layer 1 image
│   ├── tests/
│   ├── pyproject.toml
│   └── README.md
│
├── platform-bootstrap/             # Runtime services
│   ├── docker-compose.yml          # Kerberos ticket sharer
│   ├── Makefile                    # Service management
│   └── README.md
│
├── cookiecutter-layer2-datakit/    # Template for new datakits
│   ├── cookiecutter.json           # Template variables
│   └── {{cookiecutter.datakit_name}}/
│       ├── Dockerfile              # FROM layer1-airflow:latest
│       ├── dags/                   # Starter DAG templates
│       ├── docker-compose.override.yml
│       └── README.md
│
├── runtime-environments/           # Specialized container images
│   ├── spark-runner/
│   ├── dbt-runner/
│   └── sqlserver-runner/
│
└── docs/                           # Platform documentation
    ├── platform-architecture-vision.md  (this file)
    ├── getting-started-simple.md
    └── credential-management.md
```

---

## Credential Management (Secure Patterns)

**Critical Rule:** NO credentials in `.env` files or git repositories.

**Configuration Approach:** The platform uses a wizard-based setup (`./platform setup`) that creates `platform-config.yaml` for version-controlled configuration (paths only, no secrets) and auto-generates `.env` files locally. The `.env` files are git-ignored and should never be committed.

### APT Package Repositories (Dockerfile RUN apt-get)
```bash
# Developer creates ~/.netrc on their machine
machine artifactory.company.com
login myuser
password mytoken
```

Dockerfile uses netrc automatically:
```dockerfile
RUN apt-get update && apt-get install -y krb5-user
# Pulls from corporate Artifactory via ~/.netrc
```

### Python Package Repositories (UV/Pip)

**UV Configuration:** `~/.config/uv/uv.toml`
```toml
[[index]]
url = "https://artifactory.company.com/api/pypi/pypi-remote/simple"
name = "corporate-pypi"
```

**Environment Variables:** In `~/.bashrc` or `~/.zshrc`
```bash
export UV_INDEX_CORPORATE_PYPI_USERNAME=myuser
export UV_INDEX_CORPORATE_PYPI_PASSWORD=mytoken
```

**Pip Configuration:** `~/.pip/pip.conf`
```ini
[global]
index-url = https://artifactory.company.com/api/pypi/pypi-remote/simple
```

Uses `~/.netrc` for authentication.

### Docker Image Registries

**Docker Login:**
```bash
docker login artifactory.company.com
# Username: myuser
# Password: mytoken
# Credentials stored in ~/.docker/config.json (secure)
```

`platform-config.yaml` specifies paths only (no secrets):
```yaml
# platform-config.yaml - safe to commit to fork
services:
  astronomer:
    image: artifactory.company.com/docker-remote/astronomer/ap-airflow:11.10.0
  python:
    image: artifactory.company.com/docker-remote/library/python:3.11-slim
```

The wizard auto-generates `.env` files from this configuration.

Dockerfile pulls authenticated:
```dockerfile
ARG IMAGE_ASTRONOMER
FROM ${IMAGE_ASTRONOMER:-quay.io/astronomer/astro-runtime:11.10.0}
# Docker uses credentials from docker login
```

---

## Developer Workflows

### Corporate Setup Person (One-Time Configuration)

```bash
# 1. Fork the platform repository
git clone https://github.com/MyCompany/airflow-data-platform-fork.git
cd airflow-data-platform-fork

# 2. Configure credentials (NOT in git)
# - Create ~/.netrc for apt
# - Configure ~/.config/uv/uv.toml for UV
# - Run: docker login artifactory.company.com

# 3. Run platform setup wizard to configure paths and services
./platform setup
# Wizard prompts for:
#   - Corporate Artifactory URLs
#   - Image paths (Astronomer, Python, PostgreSQL, etc.)
#   - Service configurations
# Creates platform-config.yaml and auto-generates .env files

# 4. Configure corporate Kerberos
cp config/krb5.conf.example config/krb5.conf
# Edit krb5.conf with corporate realm/KDC

# 5. Build Layer 1 base image
make build
# Creates: layer1-airflow:latest (in local Docker cache)

# 6. Commit configuration to fork (paths only, no secrets)
git add platform-config.yaml config/krb5.conf
git commit -m "Configure for MyCompany infrastructure"
git push origin main

# 7. Document team setup
# Update README.md with:
# - Corporate netrc/docker login instructions
# - Fork URL for team to clone
```

### Regular Developer (Daily Usage)

```bash
# ONE-TIME SETUP
# ==============

# 1. Configure credentials (once per machine)
# - Create ~/.netrc for Artifactory
# - Configure ~/.config/uv/uv.toml
# - Run: docker login artifactory.company.com

# 2. Clone company's configured fork
git clone https://github.com/MyCompany/airflow-data-platform-fork.git
cd airflow-data-platform-fork

# 3. Run platform setup (uses company's platform-config.yaml from fork)
./platform setup
# Auto-generates .env files from committed configuration
# Result: All platform services configured

# 4. Build Layer 1 base image (uses company's Artifactory config)
cd layer1-base-image
make build
# Fast: pulls from corporate Artifactory
# Result: layer1-airflow:latest in Docker cache

# 5. Start runtime services
make platform-start
# Result: Kerberos ticket sharer and platform services running


# CREATING NEW DATAKIT
# ====================

# 5. Create new Layer 2 project from template
cd ~/projects
cookiecutter ~/airflow-data-platform-fork/cookiecutter-layer2-datakit
# Prompts:
#   datakit_name? customer-360
#   description? Customer 360 view combining CRM and marketing data

cd customer-360-datakit

# 6. Dockerfile automatically references Layer 1:
#    FROM layer1-airflow:latest  ← Found in Docker cache

# 7. Add your DAGs
# Edit dags/example_dag.py

# 8. Start Airflow
astro dev start
# Fast build: just adds your DAGs to Layer 1 base


# DAILY WORKFLOW
# ==============

# Monday morning
cd ~/airflow-data-platform-fork/platform-bootstrap
make platform-start  # Start Kerberos sharer

cd ~/projects/customer-360-datakit
astro dev start      # Build and start Airflow (fast - Layer 1 cached)

# Develop...

# Friday evening
astro dev stop
cd ~/airflow-data-platform-fork/platform-bootstrap
make platform-stop
```

---

## Docker Image Caching (Why No Registry Needed)

### Native Docker Behavior

**Key Insight:** Docker Desktop + WSL2 integration creates a **unified environment** with one shared Docker daemon.

When you run:
```bash
docker build -t layer1-airflow:latest .
```

That image sits in Docker's native cache (`/var/lib/docker/` or Docker Desktop's VM storage).

**All compose stacks on that machine share this cache automatically:**
```yaml
# In any project's Dockerfile
FROM layer1-airflow:latest  # Docker finds it in cache, no registry needed
```

### When Registry IS Needed (Out of Scope)

- **Multiple machines:** Developer A builds image, Developer B needs it → use corporate registry
- **CI/CD pipelines:** Build server → deployment targets → use corporate registry
- **Production:** Kubernetes clusters → use corporate registry

**For single-developer local development:** Docker cache is sufficient.

---

## Kerberos Integration

### Architecture

```
Developer's Windows/WSL2 Login
       ↓
Corporate Domain Kerberos Ticket (kinit or automatic)
       ↓
platform-bootstrap/docker-compose.yml
    ├── kerberos-ticket-sharer service
    │   └── Copies ticket to shared volume every 5 minutes
    └── Volume: platform_kerberos_cache:/krb5/cache
       ↓
Layer 2 Datakit docker-compose.override.yml
    └── Mounts: platform_kerberos_cache:/krb5/cache:ro
       ↓
Airflow Containers
    └── Environment: KRB5CCNAME=/krb5/cache/krb5cc
       ↓
SQL Server Connections (Windows Authentication via Kerberos)
```

### Key Design Decisions

1. **No local KDC:** Use existing corporate Kerberos infrastructure
2. **Ticket sharing:** Simple copy service, not complex sidecar
3. **Volume-based:** Named Docker volume shared across compose stacks
4. **Read-only mount:** Datakit containers read ticket, can't modify
5. **Automatic refresh:** Ticket sharer runs every 5 minutes

### Kerberos Sidecar Image

**Purpose:** Lightweight container that:
- Detects user's Kerberos ticket location (FILE:/path or DIR:/path)
- Copies ticket to shared volume
- Refreshes periodically
- Logs ticket status for debugging

**Built from:** `layer1-base-image/` includes Kerberos client libraries
**Referenced in:** `platform-bootstrap/docker-compose.yml`

---

## SQLModel Framework Integration

**Purpose:** Provide consistent data modeling patterns across all datakits

**Installation:** Baked into Layer 1 base image
```dockerfile
# In layer1-base-image/Dockerfile
COPY ../sqlmodel-framework/ /tmp/sqlmodel-framework/
RUN pip install --no-cache-dir /tmp/sqlmodel-framework/
```

**Usage in Layer 2 datakits:**
```python
# In dags/my_dag.py
from sqlmodel_framework import ReferenceTable, TransactionalTable

class Customer(ReferenceTable, table=True):
    customer_id: int
    name: str
```

**Benefits:**
- Consistent table patterns (reference vs transactional)
- Automatic triggers (systime, audit trails)
- Single source of truth for data modeling

---

## Cookiecutter Template Integration

### Existing Template: data-eng-template
**Location:** `~/repos/data-eng-template`
**Status:** Sophisticated but doesn't assume Layer 1 base
**Current Dockerfile:** `FROM apache/airflow:{{version}}-python{{py_version}}`

### New Template: cookiecutter-layer2-datakit
**Location:** `airflow-data-platform/cookiecutter-layer2-datakit/`
**Purpose:** Simplified template for Layer 2 datakits
**Key Change:** `FROM layer1-airflow:latest`

**Simplifications possible:**
- No requirements.txt for common deps (in Layer 1)
- No Kerberos client installation (in Layer 1)
- No corporate Artifactory configuration (in Layer 1)
- Focus on DAGs and business logic only

**Migration Path:**
1. Extract core structure from data-eng-template
2. Remove infrastructure concerns (moved to Layer 1)
3. Add proper volume mounting for Kerberos
4. Document Layer 1 prerequisite clearly

---

## Examples Repository Integration

**Repository:** `airflow-data-platform-examples`
**Relationship:** Demonstrates proper Layer 2 patterns

### Current State
Examples may build full images from scratch, not extending Layer 1.

### Future State (Post-Refactor)

**Prerequisites documentation:**
```markdown
# Prerequisites

## 1. Build Layer 1 Base Image

Clone and build the platform base:
```bash
git clone https://github.com/MyCompany/airflow-data-platform-fork.git
cd airflow-data-platform-fork/layer1-base-image
make build
```

This creates `layer1-airflow:latest` in your Docker cache.

## 2. Start Platform Services

```bash
cd ../platform-bootstrap
make platform-start
```

## 3. Run Examples

Each example extends Layer 1:
```bash
cd ../examples/pagila-sqlmodel-basic
astro dev start
```
```

**Example Dockerfile pattern:**
```dockerfile
FROM layer1-airflow:latest

# Just add example-specific DAGs
COPY dags/ /usr/local/airflow/dags/
```

---

## Implementation Stages

This refactor is broken into GitHub issues for incremental implementation:

### Stage 1: Documentation (Issue #15)
- ✅ Create this design document
- Document credential management patterns
- Define mono-repo structure
- Capture architectural decisions

### Stage 2: Simplification (Issue #16)
- Remove Traefik complexity (deprecated)
- Remove local registry services (unnecessary)
- Simplify platform-bootstrap to Kerberos + mocks only
- Update getting-started documentation

### Stage 3: Layer 1 Foundation (Issue #17)
- Create `layer1-base-image/` directory
- Dockerfile extending Astronomer
- platform-config.yaml for corporate paths
- Makefile for building
- Integration with sqlmodel-framework
- Corporate setup documentation

### Stage 4: Kerberos Pattern (Issue #18)
- Build on feature/kerberos-sidecar-implementation branch
- Define ticket sharer service
- Volume mounting patterns
- Testing and validation

### Stage 5: Cookiecutter Template (Issue #19)
- Create simplified Layer 2 template
- FROM layer1-airflow:latest
- Minimal corporate configuration
- Focus on DAG development

### Stage 6: Examples Alignment (Issue #20)
- Update examples to extend Layer 1
- Document prerequisites clearly
- Demonstrate proper patterns

---

## Benefits of This Architecture

### For Developers
✅ Fast Layer 2 project creation (cookiecutter)
✅ Fast builds (just adds DAGs to Layer 1 base)
✅ No corporate infrastructure configuration per project
✅ Consistent foundation across all projects
✅ Focus on business logic, not plumbing

### For Organizations
✅ One person configures, entire team benefits
✅ Standardization enforced by shared base image
✅ Easy updates (rebuild Layer 1, all projects inherit)
✅ Audit trail (fork shows corporate configuration)
✅ Onboarding: "Clone fork, make build, cookiecutter"

### For Maintainability
✅ Mono-repo with clear boundaries
✅ Independent versioning per component
✅ Docker cache eliminates registry complexity
✅ Standard credential management patterns
✅ Incremental implementation via staged issues

---

## Design Decisions Rationale

### Why Pattern B (Shared Base Image)?
**Rejected:** Pattern A (template to copy) - leads to drift, inconsistency
**Chosen:** Pattern B (buildable artifact) - guarantees consistency, fast builds

### Why No Local Registry?
**Key Insight:** Docker Desktop + WSL2 = unified environment, shared cache
**Simplification:** Removes service, port, volume, configuration complexity
**Trade-off:** Multi-machine sharing requires corporate registry (acceptable)

### Why Mono-Repo?
**Alternative:** Split into separate repos per component
**Chosen:** Mono-repo with clear boundaries
**Rationale:** Related components, coordinated releases, simpler for forks

### Why Secure Credential Management?
**Risk:** Secrets in .env files → accidentally committed to git
**Solution:** Wizard-based setup with platform-config.yaml (version-controlled, no secrets) + auto-generated .env files (git-ignored) + standard tools (netrc, docker login, uv.toml + env vars)
**Benefit:** Industry best practices, tooling support, secure by design, consistent configuration across team

### Why Kerberos Ticket Sharing (Not Sidecar)?
**Complexity:** Full sidecar adds Init container, coordination, lifecycle management
**Simplification:** Simple copy service + volume mount
**Trade-off:** Less dynamic, but sufficient for local development

---

## Success Criteria

### Developer Experience
- [ ] New developer: clone fork → make build → cookiecutter → astro dev start (< 30 min)
- [ ] Corporate setup person: configure once in fork, team benefits
- [ ] Fast builds: Layer 2 projects build in < 2 minutes (just DAGs added)
- [ ] No credential management in project files
- [ ] Clear error messages when prerequisites missing

### Technical Validation
- [ ] Layer 1 base image builds successfully with corporate Artifactory
- [ ] Kerberos ticket sharing works across compose stacks
- [ ] SQLModel framework available in all Layer 2 projects
- [ ] Cookiecutter template generates working project
- [ ] Examples repo demonstrates proper patterns

### Organizational Benefits
- [ ] Standardized foundation (same Layer 1 across team)
- [ ] Easy updates (rebuild Layer 1, all projects inherit)
- [ ] Clear separation of concerns (infrastructure vs business logic)
- [ ] Documented patterns for credential management
- [ ] Reduced onboarding friction

---

## Related Documents

- [Getting Started Guide](getting-started-simple.md)
- [Credential Management](credential-management.md) (to be created)
- [Layer 1 Build Instructions](../layer1-base-image/README.md) (to be created)
- [Cookiecutter Template Guide](../cookiecutter-layer2-datakit/README.md) (to be created)

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2025-10-11 | Initial design document created | Platform Team |
