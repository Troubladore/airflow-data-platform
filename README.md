# Airflow Data Platform

A modern data platform framework that provides table mixins, schema management, and deployment utilities for data engineering teams. Built on [Astronomer](https://www.astronomer.io/) and [SQLModel](https://sqlmodel.tiangolo.com/) with containerized infrastructure for local development and testing.

## 📦 Two Repositories, Clear Separation

- **This repo**: Platform framework and enhancement services
- **[Examples repo](https://github.com/Troubladore/airflow-data-platform-examples)**: How to use it (once platform is deployed)

## 🎯 The Problem We're Solving

Modern data teams face common challenges:
- **Multiple teams** need to share data patterns while maintaining autonomy
- **Dependency conflicts** between different teams' requirements
- **Reusable data models** need to be defined once and deployed to multiple environments
- **Self-hosted requirements** for data sovereignty and control
- **Standardized patterns** needed across Bronze → Silver → Gold data layers

This framework provides a thin layer of enterprise patterns on top of Astronomer that addresses these challenges.

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
│   - Manages Airflow lifecycle       │   Self-hosted or cloud
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

## 🏛️ Composable Services Architecture

Each platform service is **standalone and independent** - use what you need:

```
airflow-data-platform/
├── platform-infrastructure/  # Shared foundation (ALWAYS runs)
│   ├── platform-postgres     # Shared OLTP: Airflow + OpenMetadata DBs
│   └── platform_network      # Shared network for all services
├── openmetadata/            # Metadata catalog (OPTIONAL)
│   ├── elasticsearch         # Search/indexing
│   └── server                # Web UI + REST API + Backend (all-in-one)
├── kerberos/                # SQL Server auth (OPTIONAL)
│   └── sidecar               # Ticket sharing
├── pagila/                  # PostgreSQL sample data (OPTIONAL)
└── platform-bootstrap/       # Orchestrator
    └── .env                  # Toggle optional services
```

**Foundation vs Optional:**
- `platform-infrastructure/` - **Always starts** (needed for Airflow)
- Everything else - **Optional** (toggle via .env)

**Run individually:**
```bash
cd openmetadata && make setup && make start
cd kerberos && make setup && make start
```

**Or use orchestrator:**
```bash
cd platform-bootstrap
make setup           # Guided wizard - asks what you need
make platform-start  # Starts enabled services
```

## 🚀 Getting Started

**Option 1: Guided Setup (Recommended)**
```bash
cd platform-bootstrap
make setup    # Interactive wizard detects environment, configures services
```

**Option 2: Manual Quick Start**
1. **[Platform Setup Guide](docs/getting-started-simple.md)** - Deploy the enhancement services
2. **[Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world)** - Your first project

## 📚 Documentation

### Setup & Configuration
- **[Platform Setup](docs/getting-started-simple.md)** - Install platform services
- **[Kerberos Setup for WSL2](docs/kerberos-setup-wsl2.md)** - SQL Server authentication

### Patterns & Architecture
- **[SQLModel Patterns](docs/patterns/sqlmodel-patterns.md)** - Data engineering with SQLModel
- **[Runtime Environment Patterns](docs/patterns/runtime-patterns.md)** - Dependency isolation
- **[Directory Structure](docs/directory-structure.md)** - Repository organization

### Platform Runners
- **[SQLModel Runner](runners/sqlmodel-runner/README.md)** - Pre-built container for Bronze layer ETL with SQLModel, pandas, and database drivers

### Examples & Tutorials
- **[Hello World](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world)** - Simplest example
- **[Hello Kerberos](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-kerberos)** - SQL Server auth
- **[All Examples](https://github.com/Troubladore/airflow-data-platform-examples)** - Complete examples repo

## 📊 Status

| Component | Status | Purpose |
|-----------|--------|---------|
| SQLModel Framework | ✅ Production Ready | Table mixins, triggers, deployment |
| SQLModel Runner | ✅ Production Ready | Pre-built container for Bronze layer ETL |
| Kerberos Ticket Sharer | ✅ Production Ready | SQL Server auth without passwords |
| OpenMetadata | ✅ Phase 1 Complete | Data cataloging and discovery |
| Pagila Test Database | ✅ Available | PostgreSQL sample data |
| Runtime Environments | ✅ Production Ready | Dependency isolation |
| Platform Bootstrap | ✅ Simplified | Developer tools |
| Documentation | 🚧 Updating | Aligning with new vision |

## 🎯 Philosophy

> "The best platform is invisible. If developers are thinking about the platform instead of their data, we've failed."

We provide just enough glue to make Astronomer work brilliantly for enterprise data teams, then get out of the way.

---

**Questions?** Open an issue. We aim for simplicity - if something seems complex, it probably needs fixing.
