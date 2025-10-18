# Getting Started - Platform Setup

Set up the Airflow Data Platform enhancement services that work alongside Astronomer.

## 🎯 What This Does

The platform provides **enhancement services** that work alongside Astronomer for enterprise teams:

1. **Kerberos Ticket Sharer** - Enables SQL Server Windows Authentication without passwords
2. **OpenMetadata** - Data cataloging and metadata discovery (with Kerberos integration!)
3. **Pagila Test Database** - PostgreSQL sample data for examples and testing
4. **SQLModel Framework** - Provides consistent data patterns across teams

These services run locally alongside your Astronomer projects, providing an integrated data platform experience.

**Note:** All services support corporate environments (Artifactory images, internal git servers).

## 📋 Prerequisites

<details>
<summary>Click to expand prerequisites</summary>

### Required Software

```bash
# Check what you have
docker --version     # Docker Desktop or Engine
python3 --version    # Python 3.8+
```

### If Missing

**Docker**: Download [Docker Desktop](https://docker.com/products/docker-desktop)
**Python**: Use your system package manager or [python.org](https://python.org)

</details>

## 🚀 Setup Platform Services

### Option 1: Guided Setup (Recommended for First-Time Users)

Use the interactive setup wizard that guides you through every step:

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform/platform-bootstrap

# 2. Run the setup wizard
./dev-tools/setup-kerberos.sh

# The wizard will guide you through:
# ✓ Check prerequisites (Docker, krb5-user, etc.)
# ✓ Validate your krb5.conf configuration
# ✓ Help you obtain Kerberos tickets
# ✓ Auto-detect ticket location and type
# ✓ Configure .env file automatically
# ✓ Build and start platform services
# ✓ Test ticket sharing with containers
# ✓ Optionally test SQL Server connection

# 3. Setup test data (for examples)
make setup-pagila

# This automatically:
# ✓ Clones pagila repository (configurable for corporate git)
# ✓ Starts PostgreSQL with sample DVD rental data
# ✓ Connects to platform network
# ✓ Enables OpenMetadata ingestion examples
```

The setup is modular - each component can be set up independently and is idempotent (safe to rerun).

### Option 2: Manual Setup (For Experienced Users)

If you prefer manual configuration or are re-configuring an existing setup:

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Configure for your organization
cd platform-bootstrap
cp .env.example .env
# Edit .env to match your Kerberos ticket location

# 3. Get Kerberos ticket (if using SQL Server)
kinit your.username@COMPANY.COM

# 4. Start the platform services
make platform-start

# This starts (always-on):
# ✓ Kerberos sidecar (ticket sharing for SQL Server)
# ✓ Platform PostgreSQL (OLTP - metadata storage)
# ✓ OpenMetadata Server (http://localhost:8585)
# ✓ Elasticsearch (search indexing)

# 5. Setup test data (optional but recommended)
make setup-pagila

# Provides pagila sample database for:
# ✓ OpenMetadata ingestion examples
# ✓ SQLModel framework testing
# ✓ Learning SQL patterns
```

## ✅ Verify Services

Confirm the platform services are running correctly:

```bash
# Check all platform services
make platform-status

# Expected output:
# Platform Services Status:
# ========================
#
# Core Services:
# NAME                           STATUS    PORTS
# kerberos-platform-service      Up        (healthy)
# platform-postgres              Up        5432/tcp (healthy)
# openmetadata-server            Up        0.0.0.0:8585->8585/tcp (healthy)
# openmetadata-elasticsearch     Up        9200/tcp (healthy)
# pagila-postgres                Up        127.0.0.1:5432->5432/tcp (healthy)
#
# Health Checks:
#   Kerberos: ✓ Valid ticket
#   OpenMetadata: ✓ Healthy
#   PostgreSQL: ✓ Ready
#   Elasticsearch: ✓ Healthy

## 🔧 Daily Workflow

Each day when you start development:

```bash
# Morning - Get Kerberos ticket (if using SQL Server)
kinit your.username@COMPANY.COM  # Only needed for SQL Server access

# Start all platform services (one command!)
cd airflow-data-platform/platform-bootstrap
make platform-start

# This automatically starts:
# ✅ Kerberos ticket sharer (if ticket present)
# ✅ Platform PostgreSQL (Admin OLTP - OpenMetadata, Airflow metadata)
# ✅ OpenMetadata Server (http://localhost:8585)
# ✅ Elasticsearch (metadata search)

# Services are always-on - available for all your Astronomer projects

# Work on your projects...
# - Build Airflow DAGs
# - Use OpenMetadata for schema discovery
# - Connect to SQL Server via Kerberos
# - Query pagila for testing

# Evening - Stop platform services
make platform-stop
```

**🎯 Key Point**: `make platform-start` is always-on - Kerberos, OpenMetadata, and shared PostgreSQL start together. Everything you need for data platform development.

## 🎯 Next Steps

Now that platform services are running, explore how to use them:

### 1. Try OpenMetadata (Recommended First Step!)

**Access the metadata catalog:**
```bash
# Open in browser: http://localhost:8585
# Login: admin@open-metadata.org / admin

# Run an ingestion example
cd ~/repos/airflow-data-platform-examples/openmetadata-ingestion
astro dev start
# Trigger DAG: openmetadata_ingest_pagila
# See metadata appear in OpenMetadata UI!
```

**What you'll learn:**
- How to discover data across databases
- How metadata cataloging works (everything as code!)
- How Kerberos integrates with SQL Server ingestion

**Read:** [OpenMetadata Developer Journey](openmetadata-developer-journey.md) for the complete experience

### 2. Validate Kerberos Setup (if using SQL Server)

**Test SQL Server authentication:**
```bash
cd platform-bootstrap
./diagnostics/test-sql-direct.sh sqlserver01.company.com TestDB
```

**Advanced validation:**
- [Kerberos Progressive Validation](kerberos-progressive-validation.md) - Step-by-step (15-30 min)
- Proves each layer works before moving to the next

### 3. Explore Examples

**[Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world)**
- Simple Astronomer project (5 minutes)

**[OpenMetadata Ingestion](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/openmetadata-ingestion)**
- Programmatic metadata ingestion (10 minutes)
- Shows "everything as code" pattern

**[Pagila Implementations](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/pagila-implementations)**
- SQLModel framework patterns
- Bronze/Silver/Gold medallion architecture

### 4. Learn the Architecture

- [Platform Architecture Vision](platform-architecture-vision.md) - The big picture
- [OpenMetadata Integration Design](openmetadata-integration-design.md) - Metadata cataloging architecture
- [SQLModel Patterns](patterns/sqlmodel-patterns.md) - Consistent data models (if available)

## 🛑 Stop Services

When you're done for the day:

```bash
cd platform-bootstrap
make platform-stop
```

## 🚨 Troubleshooting

<details>
<summary>Click to expand troubleshooting</summary>

### Images not pulling
```bash
# Check Docker is running
docker info

# Test image pull
docker pull hello-world
# Should pull and cache automatically
```

### Kerberos tickets not working
- Run the setup wizard: `make kerberos-setup` (guides you through every step)
- Or diagnose issues: `make kerberos-diagnose` (detailed troubleshooting)
- Ensure you have valid tickets: `kinit YOUR_USERNAME@DOMAIN.COM`
- Check tickets are in the right location: `ls ~/.krb5_cache/`
- See [Kerberos Setup Guide](kerberos-setup-wsl2.md) for detailed setup

### Services won't start
- Check Docker is running: `docker info`
- Check port conflicts: `lsof -i :5000`
- Review logs: `docker-compose logs`

</details>

---

**Ready to build?** Head to the [Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world/README.md) to create your first Astronomer project with platform enhancements.
