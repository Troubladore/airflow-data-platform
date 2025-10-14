# Software Bill of Materials (SBOM)
## Airflow Data Platform

**Last Updated:** October 2025
**Platform Version:** Current main branch
**Purpose:** Comprehensive list of all Docker images and packages needed for the platform

This document tracks dependencies for corporate Artifactory registration and security scanning.

---

## 🐳 Docker Images Required

### Platform Bootstrap Images
**Used by:** `platform-bootstrap/` services

```yaml
# Kerberos Sidecar (built from source)
alpine:3.19
# Used as base for platform/kerberos-sidecar:latest
# Source: platform-bootstrap/kerberos-sidecar/Dockerfile
# APK packages: krb5, unixodbc, freetds, bash, curl
# Binary downloads: Microsoft ODBC Driver 18 (msodbcsql18, mssql-tools18)

# Mock Services
mockserver/mockserver:latest
# Used for: Mock Delinea service (local development only)
```

### Testing & Diagnostic Images
**Used by:** Diagnostic scripts and wizard

```yaml
# Diagnostic Tests (diagnose-kerberos.sh, setup-kerberos.sh)
alpine:latest
python:3.11-alpine

# Test Scripts
python:3.11-alpine
# Used in: test_kerberos_simple.py ticket sharing validation
```

### Astronomer/Airflow Images
**Used by:** Developer Airflow projects (when they run `astro dev init`)

```yaml
# Astronomer Runtime (choose version based on needs)
quay.io/astronomer/astro-runtime:11.10.0  # Airflow 3.0.6
quay.io/astronomer/astro-runtime:latest
# Or use older versions as needed:
# astrocrpublic.azurecr.io/runtime:3.0-10
```

### Development/Testing Only
**Used by:** Deprecated experimental code (not required for platform)

```yaml
# Deprecated Kerberos Testing (deprecated/kerberos-astronomer/)
gcavalcante8808/krb5-server:latest  # Mock KDC (not needed - use corporate KDC)
```

### Notes on Apache Spark
- ❌ **NOT using** `apache/spark-py` Docker image (stale, unmaintained)
- ✅ **Using** `pyspark` Python package (installed via pip/uv)
- Base: `python:3.11-slim` + `pyspark==3.5.1` package
- See runtime-environments/spark-runner/Dockerfile

---

## 🐍 Python Packages

### Core Framework Dependencies
**sqlmodel-framework** (Platform Core):
```txt
# Core ORM
sqlmodel>=0.0.25
sqlalchemy>=2.0.43
pydantic>=2.10.5

# Database Drivers
psycopg2-binary>=2.9.10
PyMySQL>=1.1.1
pyodbc>=5.2.0

# Async Support (optional)
asyncpg==0.30.0
aiomysql==0.2.0
```

### Runtime Environment Dependencies

**PostgreSQL Runner**:
```txt
psycopg[binary]==3.2.4
pandas==2.2.3
typer==0.15.1
sqlmodel>=0.0.25
```

**SQL Server Runner**:
```txt
pyodbc>=5.2.0
pandas==2.2.3
typer==0.15.1
sqlmodel>=0.0.25
pymssql>=2.3.1
```

**Spark Runner**:
```txt
pyspark==3.5.1
pandas==2.2.3
typer==0.15.1
sqlmodel>=0.0.25
pyarrow>=18.1.0
```

**DBT Runner**:
```txt
dbt-core>=1.8.0
dbt-postgres>=1.8.0
dbt-snowflake>=1.8.0
dbt-bigquery>=1.8.0
dbt-spark>=1.8.0
```

### Airflow Provider Packages
These are typically included in Astronomer Runtime but may need separate registration:

```txt
# Core Providers
apache-airflow-providers-docker>=3.14.0
apache-airflow-providers-cncf-kubernetes>=8.5.0
apache-airflow-providers-postgres>=5.13.0
apache-airflow-providers-microsoft-mssql>=3.8.0
apache-airflow-providers-apache-spark>=4.11.0

# Additional Providers
apache-airflow-providers-http>=4.14.0
apache-airflow-providers-ssh>=3.13.2
apache-airflow-providers-sftp>=4.12.0
apache-airflow-providers-amazon>=9.2.0
apache-airflow-providers-google>=10.25.0
apache-airflow-providers-databricks>=7.1.0
apache-airflow-providers-snowflake>=5.9.0
```

### Development & Testing Dependencies
```txt
# Testing
pytest>=8.3.4
pytest-cov>=6.0.0
pytest-mock>=3.14.0
faker==33.1.0
factory-boy==3.3.0
sqlalchemy-utils==0.41.2

# Code Quality
ruff>=0.8.6
mypy>=1.14.1
black>=24.12.0
pre-commit>=4.0.1
bandit>=1.8.0

# Documentation
mkdocs>=1.6.1
mkdocs-material>=9.5.50

# Profiling (optional)
memory-profiler==0.61.0
line-profiler==4.1.3
```

### Utility & Support Packages
```txt
# UV Package Manager
uv>=0.5.14

# CLI & Configuration
typer==0.15.1
pyyaml>=6.0.2
python-dotenv>=1.0.1
rich>=13.10.0

# Data Processing
pandas>=2.2.3
numpy>=2.2.1
pyarrow>=18.1.0
openpyxl>=3.1.5
xlrd>=2.0.1

# HTTP & API
requests>=2.32.3
httpx>=0.28.1
aiohttp>=3.11.11

# Monitoring & Logging
structlog>=24.6.0
python-json-logger>=3.2.1
```

---

## 🔧 System Dependencies

### APT Packages (Debian/Ubuntu)
Required for various Python packages to compile/run:

```bash
# SQL Server connectivity
gcc
g++
unixodbc
unixodbc-dev
freetds-dev
freetds-bin
tdsodbc

# Kerberos support
krb5-user
libkrb5-dev
krb5-config

# Java (for Spark)
openjdk-17-jre-headless

# PostgreSQL client
postgresql-client

# Build essentials
build-essential
libssl-dev
libffi-dev
python3-dev
git
curl
wget
ca-certificates
```

### Windows/WSL2 Dependencies
```powershell
# For Kerberos integration
MIT Kerberos for Windows
Visual C++ Redistributable
SQL Server Native Client 17
ODBC Driver 17 for SQL Server
```

---

## 📦 Microsoft Binary Downloads

### ODBC Drivers (for Kerberos Sidecar)
**Default source:** https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/

**Files needed:**
- `msodbcsql18_18.3.2.1-1_amd64.apk` (ODBC Driver 18)
- `mssql-tools18_18.3.1.1-1_amd64.apk` (SQL Server command-line tools)

**Corporate:** If your Artifactory mirrors these, set `ODBC_DRIVER_URL` in `.env`
**Example:** `https://artifactory.company.com/microsoft-binaries/odbc/v18.3`

---

## 🎯 Astronomer-Specific Requirements

### Astronomer CLI & SDK
```txt
astronomer-providers>=1.21.0
astronomer-cosmos>=1.8.0
astro-sdk-python>=1.9.0
```

### Astronomer Runtime Components
The Astronomer Runtime image includes:
- Apache Airflow 3.0.6
- All standard providers
- Celery executor support
- Kubernetes executor support
- Common Python data packages

---

## 📋 Pre-Registration Checklist

### Priority 1 - Critical for Platform Bootstrap
**Must have before running `make kerberos-setup`:**

1. **Docker Images**:
   - `alpine:3.19` (sidecar base)
   - `alpine:latest` (diagnostic tests)
   - `python:3.11-alpine` (test scripts)
   - `mockserver/mockserver:latest` (mock services)

2. **Microsoft Binaries**:
   - ODBC Driver 18 for SQL Server (msodbcsql18)
   - SQL Server Tools 18 (mssql-tools18)

3. **Astronomer Images** (for when developers create projects):
   - `quay.io/astronomer/astro-runtime:11.10.0`

### Priority 2 - Core Python Packages
**Installed via pip/uv:**

1. **SQLModel Framework** (built into Layer 1):
   - `sqlmodel>=0.0.25`
   - `sqlalchemy>=2.0.43`
   - `pydantic>=2.10.5`

2. **SQL Server Connectivity**:
   - `pyodbc>=5.2.0`
   - `pymssql>=2.3.1`

3. **Data Processing**:
   - `pandas>=2.2.3`
   - `pyspark==3.5.1`
   - `pyarrow>=18.1.0`

### Priority 2 - Runtime Dependencies
Needed for runtime environments:

1. **Database Drivers**:
   - `pymssql>=2.3.1`
   - `psycopg[binary]==3.2.4`
   - `PyMySQL>=1.1.1`

2. **Data Processing**:
   - `pyarrow>=18.1.0`
   - `numpy>=2.2.1`
   - `openpyxl>=3.1.5`

### Priority 3 - Development Tools
For development environments:

1. **Testing & Quality**:
   - `pytest>=8.3.4`
   - `ruff>=0.8.6`
   - `mypy>=1.14.1`

2. **DBT Ecosystem**:
   - `dbt-core>=1.8.0`
   - `dbt-postgres>=1.8.0`
   - `dbt-snowflake>=1.8.0`

---

## 🔐 Security Considerations

### Vulnerability Scanning Required
All images and packages should be scanned for:
- Known CVEs
- License compliance
- Supply chain risks

### Recommended Security Packages
```txt
safety>=3.2.11
pip-audit>=2.8.2
semgrep>=1.102.0
trivy  # For container scanning
```

---

## 📝 Version Pinning Strategy

### Production Recommendations
1. **Pin major.minor** versions for stability
2. **Use exact versions** for critical dependencies
3. **Regular updates** on a quarterly cycle
4. **Test upgrades** in staging first

### Example Version Constraints
```txt
# Exact version (highest stability)
sqlmodel==0.0.25

# Minor version pinning (recommended)
pandas>=2.2.3,<2.3.0

# Major version pinning (minimum)
pytest>=8.3.4,<9.0.0
```

---

## 🔄 Update Frequency

### Regular Updates Needed
- **Monthly**: Security patches
- **Quarterly**: Minor version updates
- **Annually**: Major version updates
- **As needed**: CVE responses

### Astronomer Runtime Updates
- Track Astronomer's release cycle
- Test new runtime versions before adopting
- Maintain 2-3 versions for migration periods

---

## 📞 Support Contacts

For questions about specific packages:
- **Astronomer packages**: Astronomer support
- **Database drivers**: Respective vendor support
- **Python packages**: PyPI maintainers
- **Docker images**: Docker Hub or respective registries

---

*Last Updated: January 2025*
*Next Review: April 2025*
