# Runtime Base Images Reference

**Read time: 2 minutes**

Detailed specifications for the 3 base images we provide.

## Overview

Base images are **templates** that teams extend. They contain:
- The core runtime (Python/Spark/dbt)
- Common packages everyone needs
- Enterprise patterns (logging, auth, monitoring)
- Fast package manager (`uv`)

## 1. Python Transform Base

**Purpose**: General Python data transformations

```dockerfile
FROM python:3.11-slim
```

**Pre-installed**:
- `uv` - Fast package manager
- `pandas` - Data manipulation
- `sqlalchemy` - Database connections
- `pyodbc` - SQL Server driver
- `pydantic` - Data validation

**Use when**:
- Building ETL pipelines
- Data cleaning and transformation
- API integrations
- Machine learning pipelines

**Example extension**:
```dockerfile
FROM runtime-environments/python-transform:v2.1
RUN uv pip install --system scikit-learn==1.3.0
```

## 2. PySpark Transform Base

**Purpose**: Big data processing with Apache Spark

```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv && \
    uv pip install --system pyspark==3.5.1
```

**Pre-installed**:
- OpenJDK 17 (required for Spark)
- PySpark 3.5.1 (via PyPI, not Docker image)
- Python data processing libraries
- `uv` for additional Python packages

**Use when**:
- Processing large datasets (>10GB)
- Distributed computing needed
- Complex aggregations
- Streaming data

**Why not apache/spark-py?**
- The apache/spark-py Docker image is no longer actively maintained
- Installing pyspark via pip gives us latest versions and better control
- Smaller image size (only includes what we need)
- Easier to upgrade Spark versions

**Example extension**:
```dockerfile
FROM runtime-environments/pyspark-transform:v2.1
RUN uv pip install --system delta-spark==3.1.0
```

## 3. dbt Transform Base

**Purpose**: SQL-based transformations with dbt

```dockerfile
FROM python:3.11-slim
```

**Pre-installed**:
- dbt-core 1.7
- dbt-sqlserver
- dbt-snowflake
- dbt-postgres
- Enterprise macros

**Use when**:
- SQL-based transformations
- Data modeling
- Testing data quality
- Documentation generation

**Example extension**:
```dockerfile
FROM runtime-environments/dbt-transform:v2.1
COPY profiles.yml /root/.dbt/
COPY models/ /app/models/
```

## Version Strategy

Base images follow semantic versioning:
- **Major** (v**1**.0.0): Breaking changes
- **Minor** (v1.**1**.0): New features, backward compatible
- **Patch** (v1.0.**1**): Bug fixes

Always pin to a specific version in production:
```dockerfile
# Good - pinned version
FROM runtime-environments/python-transform:v2.1.3

# Bad - unpinned
FROM runtime-environments/python-transform:latest
```

## What's Included in All Base Images

Every base image includes:
1. **Non-root user** for security
2. **Health check** endpoint
3. **Structured logging** configuration
4. **Environment variables** for configuration
5. **`/app` directory** as working directory

## Getting the Base Images

Base images are built locally and cached by Docker:

```bash
# Build from source
cd runtime-environments/spark-runner
docker build -t runtime-environments/spark-runner:latest .

# Docker caches it automatically - available to all projects
# No registry needed for single-developer environments

# Inspect the image
docker run -it --rm runtime-environments/spark-runner:latest bash
```

For team sharing or production:
- Push to corporate registry: `docker push your-company-registry.com/runtime-environments/spark-runner:v2.1`

---

**Next**: [Creating Your First Runtime Environment](runtime-creating.md)
