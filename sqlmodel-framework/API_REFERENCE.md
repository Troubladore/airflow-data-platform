# SQLModel Framework API Reference

Complete reference documentation for all public classes, methods, and utilities in the SQLModel Framework.

## Table of Contents

1. [Base Connectors](#base-connectors)
2. [Model Mixins](#model-mixins)
3. [Data Loaders](#data-loaders)
4. [Database Engines](#database-engines)
5. [Deployment Utilities](#deployment-utilities)
6. [Configuration](#configuration)

---

## Base Connectors

Database connectivity with enterprise authentication support.

### `sqlmodel_framework.base.connectors`

#### `BaseConnector`

Abstract base class for all database connectors.

```python
from sqlmodel_framework.base.connectors import BaseConnector

class BaseConnector(ABC):
    """Abstract base for database connectors"""

    def __init__(self, config: BaseConfig):
        """Initialize connector with configuration"""

    @abstractmethod
    def test_connection(self) -> bool:
        """Test if connection is valid"""

    @abstractmethod
    def get_connection(self) -> Any:
        """Get raw database connection"""

    @abstractmethod
    def get_tables(self, schema: str = "public") -> List[str]:
        """List all tables in schema"""

    @contextmanager
    def connection_context(self):
        """Context manager for safe connection handling"""
```

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `test_connection()` | `bool` | Validates connection without throwing |
| `get_connection()` | `Any` | Returns raw DB API connection |
| `get_tables(schema)` | `List[str]` | Lists all tables in specified schema |
| `connection_context()` | Context Manager | Safe connection with automatic cleanup |

---

#### `PostgresConnector`

PostgreSQL connector with Kerberos/GSSAPI authentication support.

```python
from sqlmodel_framework.base.connectors import PostgresConnector, PostgresConfig

# Standard authentication
config = PostgresConfig(
    host="db.example.com",
    port=5432,
    database="mydb",
    username="user",
    password="pass"
)

# Kerberos authentication
config = PostgresConfig(
    host="db.example.com",
    database="mydb",
    use_kerberos=True,
    gssencmode="require"  # or "prefer", "disable"
)

connector = PostgresConnector(config)
```

**Configuration Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `host` | `str` | Required | Database hostname |
| `port` | `int` | `5432` | PostgreSQL port |
| `database` | `str` | Required | Database name |
| `username` | `Optional[str]` | `None` | Username (extracted from Kerberos if None) |
| `password` | `Optional[str]` | `None` | Password (not needed for Kerberos) |
| `use_kerberos` | `bool` | `False` | Enable Kerberos authentication |
| `gssencmode` | `str` | `"prefer"` | GSSAPI encryption mode |
| `sslmode` | `str` | `"prefer"` | SSL connection mode |

**Special Features:**
- Automatic username extraction from Kerberos ticket
- Handles container root user authentication issues
- Connection pooling support
- Automatic reconnection on failure

**Example Usage:**

```python
# Kerberos in production
config = PostgresConfig(
    host="prod.database.com",
    database="analytics",
    use_kerberos=True
)
connector = PostgresConnector(config)

# Test connection
if connector.test_connection():
    # List tables
    tables = connector.get_tables("public")

    # Execute query
    with connector.connection_context() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM users")
        count = cursor.fetchone()[0]
```

---

#### `SQLServerConnector`

SQL Server connector with Windows authentication support.

```python
from sqlmodel_framework.base.connectors import SQLServerConnector, SQLServerConfig

config = SQLServerConfig(
    host="sqlserver.example.com",
    database="AdventureWorks",
    use_windows_auth=True  # NT authentication
)

connector = SQLServerConnector(config)
```

**Configuration Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `host` | `str` | Required | SQL Server hostname |
| `port` | `int` | `1433` | SQL Server port |
| `database` | `str` | Required | Database name |
| `username` | `Optional[str]` | `None` | Username (not needed for Windows auth) |
| `password` | `Optional[str]` | `None` | Password |
| `use_windows_auth` | `bool` | `False` | Enable Windows authentication |
| `driver` | `str` | Auto-detect | ODBC driver name |

---

## Model Mixins

Reusable patterns for SQLModel table definitions.

### `sqlmodel_framework.base.models`

#### `BronzeMetadata`

Mixin adding standard Bronze layer metadata fields to any table.

```python
from sqlmodel_framework.base.models import BronzeMetadata
from sqlmodel import SQLModel, Field

class MyBronzeTable(SQLModel, BronzeMetadata, table=True):
    __tablename__ = "bronze_mytable"

    id: int = Field(primary_key=True)
    name: str

    # BronzeMetadata automatically adds these fields:
    # bronze_load_timestamp: datetime (indexed)
    # bronze_source_system: str
    # bronze_source_table: str
    # bronze_source_host: str
    # bronze_extraction_method: str
```

**Fields Added:**

| Field | Type | Indexed | Description |
|-------|------|---------|-------------|
| `bronze_load_timestamp` | `datetime` | Yes | When record was loaded to Bronze |
| `bronze_source_system` | `str` | No | Source system identifier |
| `bronze_source_table` | `str` | No | Original table name |
| `bronze_source_host` | `str` | No | Source hostname/connection |
| `bronze_extraction_method` | `str` | No | How data was extracted |

**Usage Notes:**
- Always inherits after SQLModel but before `table=True`
- Timestamp is automatically indexed for performance
- All fields are required except where noted

---

#### `ReferenceTable`

Mixin for reference data tables with audit columns.

```python
from sqlmodel_framework.base.models import ReferenceTable

class CountryRef(SQLModel, ReferenceTable, table=True):
    __tablename__ = "ref_country"

    country_code: str = Field(primary_key=True)
    country_name: str

    # ReferenceTable adds:
    # created_at: datetime
    # created_by: str
    # modified_at: datetime
    # modified_by: str
    # is_active: bool (default=True)
```

**Fields Added:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `created_at` | `datetime` | `utcnow()` | Record creation time |
| `created_by` | `str` | Required | User who created record |
| `modified_at` | `datetime` | `utcnow()` | Last modification time |
| `modified_by` | `str` | Required | User who last modified |
| `is_active` | `bool` | `True` | Soft delete flag |

---

#### `TransactionalTable`

Mixin for transactional tables with full audit trail.

```python
from sqlmodel_framework.base.models import TransactionalTable

class OrderTrx(SQLModel, TransactionalTable, table=True):
    __tablename__ = "trx_order"

    order_id: int = Field(primary_key=True)
    amount: float

    # TransactionalTable adds comprehensive audit fields
```

**Fields Added:**

| Field | Type | Description |
|-------|------|-------------|
| `transaction_id` | `UUID` | Unique transaction identifier |
| `transaction_timestamp` | `datetime` | Transaction time |
| `transaction_type` | `str` | INSERT/UPDATE/DELETE |
| `transaction_user` | `str` | User performing transaction |
| `transaction_source` | `str` | Source system/application |
| `transaction_hash` | `str` | Data integrity hash |

---

#### `TemporalTable`

Mixin for temporal (time-travel) tables.

```python
from sqlmodel_framework.base.models import TemporalTable

class ProductTemporal(SQLModel, TemporalTable, table=True):
    __tablename__ = "dim_product"

    product_id: int = Field(primary_key=True)
    product_name: str
    price: float

    # TemporalTable adds:
    # valid_from: datetime
    # valid_to: datetime
    # is_current: bool
```

**Fields Added:**

| Field | Type | Description |
|-------|------|-------------|
| `valid_from` | `datetime` | Start of validity period |
| `valid_to` | `datetime` | End of validity period |
| `is_current` | `bool` | Current record flag |

---

## Data Loaders

Pipeline components for data ingestion and transformation.

### `sqlmodel_framework.base.loaders`

#### `BronzeIngestionPipeline`

Base class for Bronze layer data ingestion pipelines.

```python
from sqlmodel_framework.base.loaders import BronzeIngestionPipeline
from pathlib import Path
import pandas as pd

class MyBronzePipeline(BronzeIngestionPipeline):
    """Custom Bronze pipeline"""

    def extract_table(self, table_name: str, **kwargs) -> pd.DataFrame:
        """Implement extraction logic"""
        with self.connector.connection_context() as conn:
            query = f"SELECT * FROM {table_name}"
            return pd.read_sql(query, conn)

# Usage
pipeline = MyBronzePipeline(
    connector=my_connector,
    bronze_path=Path("/data/bronze")
)
```

**Constructor Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `connector` | `BaseConnector` | Database connector instance |
| `bronze_path` | `Path` | Base path for Bronze storage |

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `extract_table(table_name, **kwargs)` | `pd.DataFrame` | Abstract - implement extraction |
| `add_bronze_metadata(df, ...)` | `pd.DataFrame` | Adds Bronze metadata columns |
| `write_bronze(df, ...)` | `Dict[str, Path]` | Writes data to Bronze storage |
| `validate_bronze_data(df)` | `bool` | Validates Bronze data quality |

**Helper Method Details:**

```python
# add_bronze_metadata
df = pipeline.add_bronze_metadata(
    df,
    source_system="prod_db",      # Required
    source_table="customers",      # Required
    source_host="db.example.com",  # Optional
    extraction_method="full"       # Optional, default="full_snapshot"
)

# write_bronze
paths = pipeline.write_bronze(
    df,
    source_system="prod_db",
    table_name="customers",
    formats=["parquet", "json"],  # Optional, default=["parquet"]
    partition_cols=["year", "month"]  # Optional
)
# Returns: {"parquet": Path(...), "json": Path(...)}
```

---

#### `DataFactory`

Test data generation utilities.

```python
from sqlmodel_framework.base.loaders import DataFactory

factory = DataFactory()

# Generate test DataFrame
df = factory.generate_dataframe(
    num_rows=1000,
    columns={
        "id": "int_sequence",
        "name": "random_name",
        "email": "random_email",
        "amount": "random_float",
        "created": "random_datetime"
    }
)

# Generate from table class
df = factory.from_model(
    MyBronzeTable,
    num_rows=100
)
```

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `generate_dataframe(num_rows, columns)` | `pd.DataFrame` | Generate test data |
| `from_model(model_class, num_rows)` | `pd.DataFrame` | Generate from SQLModel |
| `add_noise(df, percent)` | `pd.DataFrame` | Add random nulls/noise |

---

## Database Engines

Factory methods for creating database engines.

### `sqlmodel_framework.engines`

#### `PostgresEngine`

PostgreSQL engine creation utilities.

```python
from sqlmodel_framework.engines import PostgresEngine

# Local connection
engine = PostgresEngine.create_local_engine(
    database="mydb",
    username="user",
    password="pass",
    host="localhost",
    port=5432
)

# Container for testing
engine = PostgresEngine.create_container_engine(
    database="test_db",
    port=5433  # Non-standard port
)

# Unix socket (fastest for local)
engine = PostgresEngine.create_socket_engine(
    database="mydb",
    socket_dir="/var/run/postgresql"
)
```

**Factory Methods:**

| Method | Use Case | Parameters |
|--------|----------|------------|
| `create_local_engine()` | Local development | host, port, database, user, password |
| `create_container_engine()` | Test containers | database, port, password |
| `create_socket_engine()` | Unix socket connection | database, socket_dir |
| `create_pool_engine()` | Connection pooling | Same as local + pool_size, max_overflow |

---

#### `MySQLEngine`

MySQL engine creation utilities.

```python
from sqlmodel_framework.engines import MySQLEngine

# Standard connection
engine = MySQLEngine.create_engine(
    database="mydb",
    username="root",
    password="pass",
    host="localhost",
    port=3306
)

# Container for testing
engine = MySQLEngine.create_container_engine(
    database="test_db",
    port=3307
)
```

---

#### `SQLiteEngine`

SQLite engine creation utilities.

```python
from sqlmodel_framework.engines import SQLiteEngine

# In-memory (fastest for tests)
engine = SQLiteEngine.create_memory_engine()

# File-based
engine = SQLiteEngine.create_file_engine(
    path="/tmp/test.db"
)

# Temporary (auto-cleanup)
engine = SQLiteEngine.create_temp_engine()
```

**Factory Methods:**

| Method | Use Case | Returns |
|--------|----------|---------|
| `create_memory_engine()` | Unit tests | In-memory SQLite |
| `create_file_engine(path)` | Persistent tests | File-based SQLite |
| `create_temp_engine()` | Integration tests | Temp file with cleanup |

---

## Deployment Utilities

Tools for discovering and deploying datakit objects.

### `sqlmodel_framework.utils.deployment`

#### Core Functions

```python
from sqlmodel_framework.utils.deployment import (
    discover_datakit_modules,
    discover_sqlmodel_classes,
    deploy_data_objects,
    validate_deployment
)

# Discover datakit modules
modules = discover_datakit_modules("/path/to/datakit")

# Find SQLModel tables
tables = discover_sqlmodel_classes(modules)

# Deploy to database
result = deploy_data_objects(
    tables,
    target_config,
    cleanup_first=True
)

# Validate deployment
validation = validate_deployment(
    tables,
    target_config
)
```

**Function Reference:**

| Function | Returns | Description |
|----------|---------|-------------|
| `discover_datakit_modules(path)` | `List[Module]` | Find all Python modules |
| `discover_sqlmodel_classes(modules)` | `List[Type]` | Extract SQLModel tables |
| `deploy_data_objects(tables, config)` | `Dict` | Deploy tables to database |
| `validate_deployment(tables, config)` | `Dict` | Verify deployment success |
| `cleanup_database(config)` | `bool` | Drop all tables |

**Deployment Options:**

```python
result = deploy_data_objects(
    tables,
    config,
    cleanup_first=True,      # Drop existing tables
    create_schema=True,      # Create schema if missing
    validate_after=True,     # Validate after deploy
    echo_sql=False          # Print SQL statements
)
```

---

## Configuration

Target configuration for deployments.

### `sqlmodel_framework.config.targets`

#### Predefined Targets

```python
from sqlmodel_framework.config.targets import get_target_config

# Use predefined target
config = get_target_config("sqlite_memory")
config = get_target_config("postgres_container")
config = get_target_config("postgres_local")
```

**Available Targets:**

| Target | Database | Description |
|--------|----------|-------------|
| `sqlite_memory` | SQLite | In-memory, fastest |
| `sqlite_file` | SQLite | Temporary file |
| `postgres_container` | PostgreSQL | Test container on :5433 |
| `postgres_local` | PostgreSQL | Local instance on :5432 |
| `mysql_container` | MySQL | Test container on :3307 |

#### Custom Targets

```python
from sqlmodel_framework.config.targets import create_custom_target

config = create_custom_target(
    engine_type="postgres",
    database="custom_db",
    host="db.example.com",
    port=5432,
    username="user",
    password="pass",
    options={
        "pool_size": 10,
        "echo": True
    }
)
```

#### Environment-Based Selection

```python
from sqlmodel_framework.config.targets import (
    get_ci_target,
    get_development_target,
    get_production_target
)

# Automatic selection based on environment
if os.environ.get("CI"):
    config = get_ci_target()  # SQLite memory
elif os.environ.get("ENV") == "production":
    config = get_production_target()  # Production DB
else:
    config = get_development_target()  # Local PostgreSQL
```

---

## Error Handling

### Common Exceptions

```python
from sqlmodel_framework.exceptions import (
    ConnectionError,
    AuthenticationError,
    KerberosError,
    DeploymentError,
    ValidationError
)

try:
    connector.test_connection()
except AuthenticationError as e:
    print(f"Auth failed: {e}")
except KerberosError as e:
    print(f"Kerberos issue: {e}")
except ConnectionError as e:
    print(f"Connection failed: {e}")
```

### Error Classes

| Exception | Cause | Resolution |
|-----------|-------|------------|
| `ConnectionError` | Cannot reach database | Check host/port/network |
| `AuthenticationError` | Invalid credentials | Check username/password |
| `KerberosError` | Kerberos auth failed | Check ticket/realm |
| `DeploymentError` | Table creation failed | Check permissions/schema |
| `ValidationError` | Data validation failed | Check data quality |

---

## Best Practices

### Connection Management

```python
# Good: Use context manager
with connector.connection_context() as conn:
    # Connection automatically closed
    result = pd.read_sql("SELECT * FROM table", conn)

# Bad: Manual connection management
conn = connector.get_connection()
result = pd.read_sql("SELECT * FROM table", conn)
conn.close()  # Easy to forget!
```

### Bronze Metadata

```python
# Good: Use pipeline helper
df = pipeline.add_bronze_metadata(
    df,
    source_system="prod",
    source_table="customers"
)

# Bad: Add manually
df["bronze_load_timestamp"] = datetime.now()
df["bronze_source_system"] = "prod"
# Missing other required fields!
```

### Testing Strategy

```python
# Unit tests: Use SQLite
def test_model():
    engine = SQLiteEngine.create_memory_engine()
    # Fast, isolated

# Integration tests: Use containers
def test_pipeline():
    engine = PostgresEngine.create_container_engine()
    # Real database behavior

# Production: Use actual config
def deploy_production():
    config = PostgresConfig(
        host="prod.db.com",
        use_kerberos=True
    )
```

---

## Migration Guide

### From Custom Implementation

If you built custom Bronze classes, migrate to framework:

```python
# Before: Custom implementation
class MyBronzeTable(SQLModel, table=True):
    id: int
    created_at: datetime  # Manual
    source_system: str     # Manual
    # Lots of boilerplate

# After: Using framework
class MyBronzeTable(SQLModel, BronzeMetadata, table=True):
    id: int
    # Metadata automatically added!
```

### From Raw psycopg2

```python
# Before: Raw psycopg2
import psycopg2
conn = psycopg2.connect(...)
cursor = conn.cursor()
# Manual everything

# After: Framework connector
connector = PostgresConnector(config)
with connector.connection_context() as conn:
    # Managed connection with retry logic
```

---

## Version Compatibility

| Framework Version | SQLModel | PostgreSQL | Python |
|------------------|----------|------------|--------|
| 1.0.x | 0.0.25 | 12+ | 3.9+ |
| 1.1.x | 0.0.25 | 13+ | 3.10+ |
| 2.0.x | 0.1.0 | 14+ | 3.11+ |

---

## Performance Tips

1. **Use connection pooling** for high-throughput operations
2. **Index Bronze timestamp** fields for time-based queries
3. **Batch writes** to Bronze storage for efficiency
4. **Use SQLite** for unit tests (100x faster)
5. **Partition Bronze data** by date for large datasets

---

## Troubleshooting

### Kerberos Authentication Issues

```python
# Debug Kerberos
import os
os.environ["KRB5_TRACE"] = "/dev/stderr"

# Check ticket
os.system("klist")

# Force ticket refresh
os.system("kinit -R")
```

### Container Connection Issues

```python
# Check container is running
os.system("docker ps")

# Test direct connection
os.system("psql -h localhost -p 5433 -U postgres -d test")

# Use explicit IP
config = PostgresConfig(
    host="172.17.0.2",  # Docker IP
    port=5432,
    database="test"
)
```

---

## See Also

- [Getting Started Guide](GETTING_STARTED.md)
- [Framework Examples](examples/)
- [SQLModel Documentation](https://sqlmodel.tiangolo.com/)
- [Main Repository](https://github.com/Troubladore/airflow-data-platform)