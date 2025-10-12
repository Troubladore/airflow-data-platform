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
FROM apache/spark-py:v3.5.0
```

**Pre-installed**:
- Apache Spark 3.5
- PySpark
- Delta Lake support
- `uv` for additional Python packages

**Use when**:
- Processing large datasets (>10GB)
- Distributed computing needed
- Complex aggregations
- Streaming data

**Example extension**:
```dockerfile
FROM runtime-environments/pyspark-transform:v2.1
RUN uv pip install --system koalas==1.8.2
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

Base images are available from:
- **Local development**: `registry:5000/runtime-environments/`
- **Production**: `your-company-registry.com/runtime-environments/`

Pull manually to inspect:
```bash
docker pull registry:5000/runtime-environments/python-transform:v2.1
docker run -it --rm registry:5000/runtime-environments/python-transform:v2.1 bash
```

---

**Next**: [Creating Your First Runtime Environment](runtime-creating.md)
