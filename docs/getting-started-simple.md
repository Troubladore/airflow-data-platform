# Getting Started - Platform Setup

Set up the Airflow Data Platform enhancement services that work alongside Astronomer.

## 🎯 What This Does

The platform provides **enhancement services** that work alongside Astronomer for enterprise teams:

1. **Kerberos Ticket Sharer** - Enables SQL Server Windows Authentication without passwords
2. **OpenMetadata** - Data cataloging and metadata discovery across all your databases
3. **Pagila Test Database** - PostgreSQL sample data for examples and testing
4. **SQLModel Framework** - Provides consistent data patterns across teams

These services run locally alongside your Astronomer projects, providing an integrated data platform experience.

**Note:** All services are **idempotent** (safe to rerun) and support custom Docker images (private registries, pre-built images, corporate Artifactory).

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

# The wizard will:
# ✓ Check prerequisites (Docker, krb5-user, etc.)
# ✓ Validate your krb5.conf configuration
# ✓ Help you obtain Kerberos tickets
# ✓ Auto-detect ticket location and type
# ✓ Configure .env file automatically
# ✓ Build and start all platform services
# ✓ Test ticket sharing with containers
# ✓ Optionally test SQL Server connection

# 3. Setup test data (optional but recommended for examples)
make setup-pagila

# This automatically:
# ✓ Clones pagila repository (configurable for corporate git)
# ✓ Starts PostgreSQL with sample DVD rental data
# ✓ Connects to platform network
# ✓ Enables OpenMetadata ingestion examples
```

The setup is **modular and idempotent** - each component can be set up independently and is safe to rerun.

### Option 2: Manual Setup (For Experienced Users)

If you prefer manual configuration or are re-configuring an existing setup:

```bash
# 1. Clone the platform repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform/platform-bootstrap

# 2. Configure for your organization
cp .env.example .env
# Edit .env for corporate images/git (if needed)

# 3. Get Kerberos ticket (if using SQL Server)
kinit your.username@COMPANY.COM

# 4. Start the platform services
make platform-start

# This starts (always-on):
# ✓ Kerberos sidecar (ticket sharing for SQL Server)
# ✓ Platform PostgreSQL (metadata storage)
# ✓ OpenMetadata Server (http://localhost:8585)
# ✓ Elasticsearch (search indexing)

# 5. Setup test data (optional)
make setup-pagila
```

## ✅ Verify Services

Confirm the platform services are running correctly:

```bash
# Check all platform services
make platform-status

# You should see:
# - Kerberos sidecar (if ticket present)
# - Platform PostgreSQL (Admin OLTP)
# - OpenMetadata Server
# - Elasticsearch
# - Pagila PostgreSQL (if setup-pagila was run)
```

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
# ✅ Platform PostgreSQL (OpenMetadata, Airflow metadata)
# ✅ OpenMetadata Server (http://localhost:8585)
# ✅ Elasticsearch (metadata search)

# Work on your Astronomer projects...
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

**Try OpenMetadata (Recommended First!):**
- Open http://localhost:8585 (login: `admin@open-metadata.org` / `admin`)
- Run ingestion example: [OpenMetadata Ingestion DAGs](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/openmetadata-ingestion)
- **Read:** [OpenMetadata Developer Journey](openmetadata-developer-journey.md) for the complete experience

**Validate Kerberos (if using SQL Server):**
- Test: `./diagnostics/test-sql-direct.sh sqlserver01.company.com TestDB`
- Advanced: [Kerberos Progressive Validation](kerberos-progressive-validation.md)

**Explore Examples:**
- [Hello World](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world) - Simple Astronomer project
- [Pagila Implementations](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/pagila-implementations) - SQLModel patterns

**Learn the Architecture:**
- [Platform Architecture Vision](platform-architecture-vision.md)
- [OpenMetadata Integration Design](openmetadata-integration-design.md)

## 🐳 Using Custom Docker Images

The platform fully supports custom Docker images, whether you're in a corporate environment with private registries or just want full control over your image builds.

**Why use custom images?**
- **Security**: Pre-scan and approve all dependencies
- **Performance**: Pre-install packages to avoid runtime downloads
- **Compliance**: Include corporate certificates and configurations
- **Reproducibility**: Know exactly what's in your images

**Quick Start:**
```bash
# Configure custom images in platform-bootstrap/.env
IMAGE_PYTHON=myorg/python:3.11-custom
IMAGE_POSTGRES=myorg/postgres:17.5-custom
IMAGE_KERBEROS_TEST=myorg/kerberos-test:3.11

# Set mode to use pre-built images (optional)
IMAGE_MODE=prebuilt  # Skip runtime package installation
```

**Learn More:**
- [Custom Image Requirements](custom-image-requirements.md) - Full specifications and Dockerfile examples
- [Sample Dockerfiles](dockerfiles/) - Ready-to-use templates for each image type

The platform works with both standard Docker Hub images and your custom-built images seamlessly.

## 🚨 Troubleshooting

<details>
<summary>Click to expand troubleshooting</summary>

### Services won't start
```bash
make platform-status  # Check what's wrong
docker info          # Verify Docker is running
```

### Kerberos tickets not working
- Run: `./dev-tools/setup-kerberos.sh` (guides you through setup)
- Or: `make kerberos-diagnose` (detailed diagnostics)
- Ensure valid ticket: `kinit YOUR_USERNAME@DOMAIN.COM`

### OpenMetadata not accessible
- Check services: `make platform-status`
- Wait for startup (first start takes 2-3 minutes)
- Check health: `curl http://localhost:8585/api/v1/health`

### Pagila not found
- Run: `make setup-pagila` (clones and starts automatically)
- Verify: `docker ps | grep pagila-postgres`

### Cleanup / Teardown (Iterative Testing)

**Remove specific services:**
```bash
make clean-openmetadata  # Just OpenMetadata (asks about data volumes)
make clean-pagila        # Just Pagila (removes volumes)
make clean-kerberos      # Just Kerberos sidecar
```

**Full cleanup:**
```bash
make clean-slate         # Interactive (asks about each component)
make clean-all           # Non-interactive (removes everything)
```

**What gets preserved:**
- Your `.env` configuration
- Built Docker images (unless you choose to remove)
- Host-side Kerberos tickets (unless you choose to clear)

**Note:** `clean-openmetadata` asks before removing data volumes since your cataloged metadata is valuable work product!

</details>

---

**Ready to build?** Head to the [OpenMetadata Developer Journey](openmetadata-developer-journey.md) or [Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world/README.md) to see the platform in action.
