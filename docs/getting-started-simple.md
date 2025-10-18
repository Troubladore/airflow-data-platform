# Getting Started

**Get the platform running in 15 minutes.**

---

## What You Get

Platform services that enhance Astronomer:
- **Kerberos** - SQL Server auth without passwords
- **OpenMetadata** - Data catalog and discovery
- **Pagila** - PostgreSQL test data
- **SQLModel** - Consistent data patterns

---

## Setup

```bash
# 1. Clone
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform/platform-bootstrap

# 2. Run setup wizard
./dev-tools/setup-kerberos.sh

# 3. Setup test data (optional)
make setup-pagila

# 4. Verify
make platform-status
```

**That's it!** Services are running.

---

## Daily Use

```bash
# Start platform
make platform-start

# Your work here...

# Stop platform
make platform-stop
```

**Drill-through:** [Platform Daily Workflow](platform-daily-workflow.md)

---

## Try It Out

**OpenMetadata:**
- UI: http://localhost:8585
- Login: `admin@open-metadata.org` / `admin`
- **Read:** [OpenMetadata Developer Journey](openmetadata-developer-journey.md) ⭐

**Examples:**
- [OpenMetadata Ingestion](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/openmetadata-ingestion)
- [Hello World](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world)

---

## Learn More

**Architecture:**
- [Platform Architecture Vision](platform-architecture-vision.md)
- [OpenMetadata Integration](openmetadata-integration-design.md)

**Operations:**
- [Daily Workflow](platform-daily-workflow.md) ← Morning/evening routine
- [Corporate Setup](platform-corporate-setup.md) ← Artifactory, internal git
- [Troubleshooting](platform-troubleshooting.md) ← When things break

**Advanced:**
- [Kerberos Setup Details](kerberos-setup-wsl2.md)
- [Kerberos Diagnostics](kerberos-diagnostic-guide.md)

---

**Questions?** Check the drill-through guides linked above.
