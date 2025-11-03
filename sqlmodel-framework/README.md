# Data Platform Framework

**🏗️ Comprehensive framework library for data platform infrastructure**

This framework provides the foundational patterns and utilities for our entire data platform:
- **Layer 2**: Component testing with data object deployment
- **Layer 3**: Pipeline orchestration and integration testing
- **Production**: Deployment patterns for live data systems

Extracted and adapted from medallion-demo patterns for enterprise-scale data platform operations.

## 🎯 Architecture Philosophy

- **Layer 2 Use**: Deploy individual datakit objects to disposable test databases for unit testing
- **Layer 3 Use**: Reuse deployment patterns for pipeline orchestration and integration testing
- **Multi-Database**: Support postgres, mysql, sqlite with configurable test targets
- **Disposable**: Create/destroy test environments rapidly for reliable testing

## 🚀 Quick Start

### Deploy a Datakit to SQLite (Fastest)
```bash
cd data-platform-framework
python scripts/deploy_datakit.py /path/to/bronze-pagila --target sqlite_memory --validate
```

### Deploy to PostgreSQL Container
```bash
python scripts/deploy_datakit.py /path/to/bronze-pagila --target postgres_container --validate
```

### Custom Target Configuration
```bash
python scripts/deploy_datakit.py /path/to/bronze-pagila \
  --target-type postgres \
  --database test_bronze_pagila \
  --host localhost \
  --port 5433 \
  --validate --cleanup
```

### List Available Targets
```bash
python scripts/deploy_datakit.py --list-targets
```

## 🗂️ Framework Structure

```
data-platform-framework/
├── base/                       # Base classes and patterns
│   ├── connectors/            # Database connectors
│   │   ├── base.py           # BaseConnector abstract class
│   │   └── postgres.py       # PostgresConnector with Kerberos
│   ├── models/                # Table mixins and patterns
│   │   ├── table_mixins.py   # Reference, Transactional, Temporal
│   │   └── bronze_metadata.py # Bronze layer metadata mixin
│   └── loaders/               # Data loading pipelines
│       └── bronze_ingestion.py # Bronze layer ingestion base
├── engines/                    # Database engine factories
│   ├── postgres_engine.py     # PostgreSQL connections & containers
│   ├── mysql_engine.py        # MySQL connections & containers
│   └── sqlite_engine.py       # SQLite in-memory & file databases
├── utils/                      # Core deployment utilities
│   └── deployment.py          # Discovery, deployment, validation
├── config/                     # Test target configurations
│   └── targets.py             # Predefined & custom targets
├── scripts/                    # CLI deployment tools
│   └── deploy_datakit.py      # Main deployment script
└── tests/                      # Framework tests
```

## 🎛️ Predefined Test Targets

| Target | Database | Speed | Use Case |
|--------|----------|-------|----------|
| `sqlite_memory` | SQLite | ⚡ Fastest | Unit tests, CI/CD |
| `sqlite_file` | SQLite | 🚀 Fast | Persistent testing |
| `postgres_container` | PostgreSQL | 🐌 Medium | Integration tests |
| `postgres_local` | PostgreSQL | 🚀 Fast | Local development |
| `mysql_container` | MySQL | 🐌 Medium | Cross-database tests |

## 🔧 Engine Support

### PostgreSQL Engine
- **Connection methods**: password, tcp, unix socket
- **Container support**: Test containers on non-standard ports
- **Local development**: Unix socket connections for speed

### MySQL Engine
- **Connection methods**: password-based authentication
- **Container support**: Test containers with custom configurations
- **Cross-platform**: Works on Windows, macOS, Linux

### SQLite Engine
- **In-memory**: Fastest for unit tests (`:memory:`)
- **File-based**: Persistent testing in temp directories
- **No setup**: Zero configuration required

## 🥉 Bronze Layer Base Classes

### Database Connectors with Kerberos Support

The framework provides base classes for database connectivity, including Kerberos authentication support critical for containerized environments:

```python
from sqlmodel_framework.base.connectors import PostgresConnector, PostgresConfig

# Configure PostgreSQL with Kerberos
config = PostgresConfig(
    host="pgserver.example.com",
    database="pagila",
    use_kerberos=True,
    gssencmode="require"
)

# Connect and extract tables
connector = PostgresConnector(config)
if connector.test_connection():
    tables = connector.get_tables(schema="public")
    with connector.connection_context() as conn:
        # Use connection for data extraction
        pass
```

### Bronze Metadata Mixin

Add standard Bronze layer metadata to any table:

```python
from sqlmodel import SQLModel, Field
from sqlmodel_framework.base.models import BronzeMetadata

class FilmBronze(BronzeMetadata, SQLModel, table=True):
    """Bronze layer film table with metadata"""
    __tablename__ = "film_bronze"

    film_id: int = Field(primary_key=True)
    title: str
    description: str
    release_year: int
    # BronzeMetadata adds:
    # - bronze_load_timestamp
    # - bronze_source_system
    # - bronze_source_table
    # - bronze_source_host
    # - bronze_extraction_method
```

### Bronze Ingestion Pipeline

Base class for Bronze layer data ingestion:

```python
from sqlmodel_framework.base.loaders import BronzeIngestionPipeline
import pandas as pd

class PagilaBronzeLoader(BronzeIngestionPipeline):
    """Custom Bronze loader for Pagila database"""

    def extract_table(self, table_name: str) -> pd.DataFrame:
        """Extract data from source table"""
        with self.connector.connection_context() as conn:
            return pd.read_sql(f"SELECT * FROM {table_name}", conn)

# Usage
connector = PostgresConnector(config)
loader = PagilaBronzeLoader(connector, bronze_path=Path("/data/bronze"))

# Extract and add metadata
df = loader.extract_table("film")
df = loader.add_bronze_metadata(
    df,
    source_system="pagila_kerberos",
    source_table="film",
    source_host="pgserver.example.com",
    extraction_method="full_snapshot"
)

# Write to Bronze storage
paths = loader.write_bronze(
    df,
    source_system="pagila_kerberos",
    table_name="film",
    formats=["parquet", "json"]
)
```

## 📦 Framework API

### Core Functions

```python
from utils.deployment import (
    discover_datakit_modules,
    discover_sqlmodel_classes,
    deploy_data_objects,
    validate_deployment,
    create_engine_for_target
)
from config.targets import get_target_config

# Discover datakit objects
modules = discover_datakit_modules("/path/to/bronze-pagila")
table_classes = discover_sqlmodel_classes(modules)

# Configure target
target_config = get_target_config("postgres_container")

# Deploy and validate
result = deploy_data_objects(table_classes, target_config)
validation = validate_deployment(table_classes, target_config)
```

### Target Configuration

```python
# Predefined targets
config = get_target_config("sqlite_memory")

# Custom targets
config = create_custom_target(
    "postgres",
    "test_db",
    host="localhost",
    port=5433,
    user="postgres",
    password="test"
)

# Environment-specific
config = get_ci_target()        # SQLite in-memory
config = get_development_target()  # Local PostgreSQL
```

## 🧪 Testing Integration

### Layer 2 Component Testing
```python
# In component test suite
def test_bronze_pagila_tables():
    target = get_target_config("sqlite_memory")

    modules = discover_datakit_modules("../bronze-pagila")
    tables = discover_sqlmodel_classes(modules)

    result = deploy_data_objects(tables, target)
    assert result["success"]

    validation = validate_deployment(tables, target)
    assert validation["success"]
```

### Layer 3 Pipeline Testing
```python
# In pipeline integration tests
def test_full_pipeline():
    target = get_target_config("postgres_container")

    # Deploy bronze layer
    bronze_tables = discover_sqlmodel_classes(bronze_modules)
    deploy_data_objects(bronze_tables, target)

    # Deploy silver layer
    silver_tables = discover_sqlmodel_classes(silver_modules)
    deploy_data_objects(silver_tables, target)

    # Run pipeline validation
    validate_pipeline_flow(target)
```

## 🐳 Container Integration

The framework assumes you'll use Docker containers for database testing:

```bash
# PostgreSQL test container
docker run -d --name postgres-test \
  -e POSTGRES_PASSWORD=postgres \
  -p 5433:5432 \
  postgres:15.8

# MySQL test container
docker run -d --name mysql-test \
  -e MYSQL_ROOT_PASSWORD=test_pass \
  -p 3307:3306 \
  mysql:8.0
```

## 🔄 Layer 3 Reuse

This framework is designed to be imported and reused by Layer 3:

```python
# In Layer 3 orchestration
from layer2_datakits_framework.utils.deployment import deploy_data_objects
from layer2_datakits_framework.config.targets import get_integration_target

def setup_pipeline_environment():
    target = get_integration_target()

    # Deploy all datakit components
    for datakit_path in datakit_paths:
        modules = discover_datakit_modules(datakit_path)
        tables = discover_sqlmodel_classes(modules)
        deploy_data_objects(tables, target)
```

## 🚨 Framework Requirements

### Quick Installation
```bash
# Install production dependencies
uv sync --no-dev

# Or add to existing project
uv add sqlmodel==0.0.25 sqlalchemy==2.0.43 psycopg2-binary==2.9.10
```

### Development Installation
```bash
# Install with development dependencies
uv sync --extra dev --extra testing --extra async

# Complete development setup with pre-commit hooks
make setup-dev
```

### Core Dependencies (Latest Versions)
- **SQLModel 0.0.25** (Sep 2025) - Data modeling and FastAPI integration
- **psycopg2-binary 2.9.10** (Oct 2024) - PostgreSQL adapter
- **PyMySQL 1.1.1** - MySQL adapter
- **SQLAlchemy 2.x** - SQL toolkit (required by SQLModel)
- **Pydantic 2.x** - Data validation (required by SQLModel)

### Database Support
- **SQLite**: Built into Python standard library (no additional install)
- **PostgreSQL**: psycopg2-binary for production, asyncpg for async operations
- **MySQL**: PyMySQL for synchronous, aiomysql for async operations

## 🎯 Design Principles

1. **Disposable Targets**: All test databases are temporary and replaceable
2. **Multi-Engine**: Support multiple database types for compatibility testing
3. **Configuration-Driven**: Easy to customize targets without code changes
4. **Framework Reuse**: Same patterns work in Layer 2 and Layer 3
5. **Fast Feedback**: Optimized for rapid test cycles

---

**🏗️ Framework Objective**: Enable rapid, reliable testing of data objects against multiple database targets while maintaining consistency between Layer 2 component testing and Layer 3 pipeline orchestration.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
