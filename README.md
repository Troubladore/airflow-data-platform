# Airflow Data Platform - Enterprise Extensions for Astronomer

A thin layer of enterprise patterns and tools that enhance Astronomer for production data engineering.

**Not a platform replacement** - Astronomer IS the platform. We just make it better for enterprise teams.

## 🏢 Our Enterprise Context

We're building data infrastructure for a **federated enterprise** where:
- **Multiple business units** operate similar data warehouses with shared patterns
- **Self-hosted Astronomer** provides control and data sovereignty
- **Teams need autonomy** but within enterprise standards and governance
- **Define once, deploy many** - reusable data models across business units
- **Medallion architecture** (Bronze → Silver → Gold) standardizes our data flow

This repository provides the thin glue layer that makes this work at enterprise scale.

## 🏗️ Architecture Stack

```
┌─────────────────────────────────────┐
│   Your Business Logic (DAGs)        │ ← Business-specific workflows
├─────────────────────────────────────┤
│   Our Patterns (This Repo)          │ ← Enterprise standards
│   - SQLModel for data models        │   "Define once, deploy many"
│   - Runtime environments for teams  │   Team autonomy with isolation
│   - Bootstrap for developers        │   Quick local development
├─────────────────────────────────────┤
│   Astronomer Platform               │ ← Orchestration layer
│   - Manages Airflow lifecycle       │   Self-hosted for control
│   - Provides UI and monitoring      │   Enterprise authentication
├─────────────────────────────────────┤
│   Apache Airflow                    │ ← Workflow engine
│   - Executes DAGs                   │   Industry standard
│   - Schedules and dependencies      │   Battle-tested
├─────────────────────────────────────┤
│   Docker/Kubernetes                 │ ← Execution layer
│   - Container isolation             │   Local: Docker
│   - Resource management             │   Prod: Kubernetes
└─────────────────────────────────────┘
```

## 🎯 What We Provide

### 1. **SQLModel Framework** - Define Once, Deploy Many
Enables shared data models across business units:
```python
from sqlmodel_framework import ReferenceTable, deploy_data_objects

class Customer(ReferenceTable):
    """Same model deployed to unit-specific warehouses"""
    customer_id: str
    name: str
    email: str
    # Auto-adds: created_at, updated_at, audit columns

# Deploy to any business unit's warehouse
deploy_data_objects([Customer], target="business_unit_a")
deploy_data_objects([Customer], target="business_unit_b")
```
→ [Learn more about SQLModel Framework](data-platform/sqlmodel-workspace/sqlmodel-framework/README.md)

### 2. **Runtime Environments** - Team Autonomy
Enable teams to use their tools without conflicts:
```python
# Analytics team uses pandas 1.5, ML team uses pandas 2.0
# Each business unit can have different requirements

# Business Unit A - Analytics focus
analytics_transform = DockerOperator(
    image='runtime-environments/python-transform:unit-a-analytics',
    # Their specific pandas, statsmodels, etc.
)

# Business Unit B - ML focus
ml_transform = DockerOperator(
    image='runtime-environments/python-transform:unit-b-ml',
    # Their specific pytorch, tensorflow, etc.
)
```
→ [Learn more about Runtime Environments](runtime-environments/README.md)

### 3. **Simple Developer Tools**
Registry caching and Kerberos ticket sharing without complexity:
```bash
cd platform-bootstrap
make start  # That's it - registry cache + ticket sharing running
```
→ [Learn more about Platform Bootstrap](platform-bootstrap/README.md)

## 🚀 Quick Start (10 minutes)

### Prerequisites
```bash
# You probably already have these
docker --version     # Docker Desktop or Engine
astro version       # Astronomer CLI
python3 --version   # Python 3.8+
```

### Setup
```bash
# 1. Clone this repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Start minimal platform services
cd platform-bootstrap
make start  # Starts registry cache + ticket sharer

# 3. Create your Astronomer project
cd ~/projects
astro dev init my-project

# 4. Add our frameworks (optional)
cd my-project
# Add to requirements.txt:
# sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@main#subdirectory=data-platform/sqlmodel-workspace/sqlmodel-framework

# 5. Start Airflow
astro dev start
```

Your Airflow is now running at http://localhost:8080 with our enterprise enhancements available!

## 📚 Documentation Layers

Start here, drill down as needed:

### Layer 1: Understanding (You are here)
- **This README** - What and why

### Layer 2: Using
- **[Getting Started](docs/getting-started-simple.md)** - First project in 10 minutes
- **[Kerberos Setup for WSL2](docs/kerberos-setup-wsl2.md)** - SQL Server authentication guide
- **[Platform Bootstrap](platform-bootstrap/README.md)** - Developer environment setup

### Layer 3: Patterns
- **[SQLModel Patterns](docs/patterns/sqlmodel-patterns.md)** - Data engineering with SQLModel
- **[Runtime Environment Patterns](docs/patterns/runtime-patterns.md)** - Dependency isolation strategies

### Layer 4: Reference
- **[Directory Structure](docs/directory-structure.md)** - Complete repository organization
- **[Security Risk Acceptance](docs/security-risk-acceptance.md)** - Security model and decisions

## 🤔 What This Is NOT

- ❌ **Not a platform** - Astronomer is the platform
- ❌ **Not a replacement** - We enhance, not replace
- ❌ **Not complex** - If it's complex, we're doing it wrong
- ❌ **Not required** - Astronomer works fine without us

## ✅ What This IS

- ✅ **Patterns** - Proven enterprise patterns for data engineering
- ✅ **Tools** - Simple tools that solve real problems
- ✅ **Frameworks** - Reusable code for common tasks
- ✅ **Thin layer** - Minimal overhead on top of Astronomer

## 🏗️ Repository Structure

```
airflow-data-platform/
├── sqlmodel-framework/        # Core data engineering framework
│   ├── src/                  # Reusable patterns
│   └── tests/                # Comprehensive test suite
│
├── runtime-environments/      # Dependency isolation containers
│   ├── base-images/          # Standard transformation environments
│   └── patterns/             # Usage patterns and examples
│
├── platform-bootstrap/        # Developer environment setup
│   ├── registry-cache.yml    # Offline development support
│   ├── ticket-sharer.yml     # Kerberos ticket sharing
│   └── Makefile              # Simple commands
│
└── docs/                     # Layered documentation
    ├── getting-started-simple.md
    ├── patterns/             # How to use effectively
    └── reference/            # Detailed specifications
```

→ **[See complete directory structure](docs/directory-structure.md)** for full repository organization

## 🤝 For Business Teams

**Looking for examples?** See [airflow-data-platform-examples](https://github.com/Troubladore/airflow-data-platform-examples) for:
- Complete Pagila implementations
- Bronze/Silver/Gold medallion patterns
- Multi-warehouse deployments
- Production-ready DAGs

## 🔄 For Existing Users

**Migrating from v1?** We've massively simplified:
- Removed complex Ansible deployment → Use Astronomer CLI
- Removed Traefik complexity → Simple Docker networking
- Removed layer1-platform → Astronomer provides this
- Kept the valuable patterns → SQLModel, runtime environments

See [Migration Guide](docs/migration-from-v1.md) for details.

## 📊 Status

| Component | Status | Purpose |
|-----------|--------|---------|
| SQLModel Framework | ✅ Production Ready | Table mixins, triggers, deployment |
| Runtime Environments | ✅ Production Ready | Dependency isolation |
| Platform Bootstrap | ✅ Simplified | Developer tools |
| Documentation | 🚧 Updating | Aligning with new vision |

## 🎯 Philosophy

> "The best platform is invisible. If developers are thinking about the platform instead of their data, we've failed."

We provide just enough glue to make Astronomer work brilliantly for enterprise data teams, then get out of the way.

---

**Questions?** Open an issue. We aim for simplicity - if something seems complex, it probably needs fixing.
