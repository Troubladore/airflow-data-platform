# Getting Started with SQLModel Framework

This guide will help you build your first datakit using the SQLModel Framework. By the end of this guide, you'll understand how to leverage the framework's base classes instead of building everything from scratch.

## Table of Contents

1. [Installation](#installation)
2. [Understanding the Framework](#understanding-the-framework)
3. [Building Your First Bronze Datakit](#building-your-first-bronze-datakit)
4. [Advanced Features](#advanced-features)
5. [Testing Your Datakit](#testing-your-datakit)
6. [Next Steps](#next-steps)

## Installation

### Adding the Framework to Your Datakit

Add the framework to your datakit's `pyproject.toml`:

```toml
[project]
name = "my-bronze-datakit"
version = "0.1.0"
dependencies = [
    "sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@main#subdirectory=sqlmodel-framework",
    "pandas>=2.0.0",
    "psycopg2-binary>=2.9.0",  # For PostgreSQL
]
```

Then install with:
```bash
uv sync
```

## Understanding the Framework

The framework provides battle-tested base classes so you don't have to reinvent the wheel. Here's what's available:

### Core Components

| Component | Purpose | Import From |
|-----------|---------|-------------|
| **Connectors** | Database connectivity with auth support | `sqlmodel_framework.base.connectors` |
| **Models** | Table mixins and metadata patterns | `sqlmodel_framework.base.models` |
| **Loaders** | Data ingestion pipelines | `sqlmodel_framework.base.loaders` |
| **Engines** | Database engine factories | `sqlmodel_framework.engines` |

### Key Benefits

✅ **Kerberos Authentication**: Built-in support for enterprise auth
✅ **Bronze Metadata**: Standardized tracking fields
✅ **Connection Management**: Proper pooling and cleanup
✅ **Testing Support**: Works with test containers

## Building Your First Bronze Datakit

Let's build a Bronze layer datakit that extracts data from a PostgreSQL database.

### Step 1: Import Framework Components

```python
# datakit/connectors.py
from sqlmodel_framework.base.connectors import PostgresConnector, PostgresConfig
from sqlmodel_framework.base.models import BronzeMetadata
from sqlmodel_framework.base.loaders import BronzeIngestionPipeline
from sqlmodel import SQLModel, Field
from datetime import datetime
from typing import Optional
import pandas as pd
from pathlib import Path
```

### Step 2: Configure Your Database Connection

```python
# Standard connection with username/password
config = PostgresConfig(
    host="database.example.com",
    port=5432,
    database="pagila",
    username="datauser",
    password="securepass"
)

# OR: Kerberos authentication (for production)
config = PostgresConfig(
    host="database.example.com",
    port=5432,
    database="pagila",
    use_kerberos=True,  # Framework handles auth!
    gssencmode="require"
)

# Create connector
connector = PostgresConnector(config)

# Test connection
if connector.test_connection():
    print("Connected successfully!")
    tables = connector.get_tables(schema="public")
    print(f"Found {len(tables)} tables")
```

### Step 3: Define Your Bronze Tables

The framework provides `BronzeMetadata` mixin that adds standard Bronze layer fields:

```python
# datakit/models.py
class FilmBronze(SQLModel, BronzeMetadata, table=True):
    """Bronze layer film table with automatic metadata tracking"""
    __tablename__ = "bronze_film"

    # Your business fields
    film_id: int = Field(primary_key=True)
    title: str
    description: Optional[str] = None
    release_year: Optional[int] = None
    rental_duration: int
    rental_rate: float
    length: Optional[int] = None
    replacement_cost: float
    rating: Optional[str] = None

    # BronzeMetadata automatically adds:
    # - bronze_load_timestamp: datetime (indexed)
    # - bronze_source_system: str
    # - bronze_source_table: str
    # - bronze_source_host: str
    # - bronze_extraction_method: str

class ActorBronze(SQLModel, BronzeMetadata, table=True):
    """Bronze layer actor table"""
    __tablename__ = "bronze_actor"

    actor_id: int = Field(primary_key=True)
    first_name: str
    last_name: str
    last_update: datetime
```

### Step 4: Create Your Ingestion Pipeline

Extend the framework's `BronzeIngestionPipeline`:

```python
# datakit/pipeline.py
class PagilaBronzeLoader(BronzeIngestionPipeline):
    """Custom Bronze loader for Pagila database"""

    def extract_table(self, table_name: str, limit: Optional[int] = None) -> pd.DataFrame:
        """Extract data from source table"""
        with self.connector.connection_context() as conn:
            query = f"SELECT * FROM {table_name}"
            if limit:
                query += f" LIMIT {limit}"

            df = pd.read_sql(query, conn)

            # Add Bronze metadata (framework helper)
            return self.add_bronze_metadata(
                df,
                source_system='pagila_prod',
                source_table=table_name,
                source_host=self.connector.config.host,
                extraction_method='full_snapshot'
            )

    def extract_incremental(self, table_name: str, last_timestamp: datetime) -> pd.DataFrame:
        """Extract only new/changed records since last run"""
        with self.connector.connection_context() as conn:
            query = f"""
                SELECT * FROM {table_name}
                WHERE last_update > '{last_timestamp}'
            """
            df = pd.read_sql(query, conn)

            return self.add_bronze_metadata(
                df,
                source_system='pagila_prod',
                source_table=table_name,
                source_host=self.connector.config.host,
                extraction_method='incremental'
            )
```

### Step 5: Run Your Pipeline

```python
# datakit/main.py
def run_bronze_ingestion():
    """Main ingestion workflow"""

    # Setup
    config = PostgresConfig(
        host="pgserver.example.com",
        database="pagila",
        use_kerberos=True
    )
    connector = PostgresConnector(config)

    # Create pipeline with Bronze storage path
    bronze_path = Path("/data/bronze/pagila")
    loader = PagilaBronzeLoader(connector, bronze_path=bronze_path)

    # Define tables to extract
    tables_to_extract = ['film', 'actor', 'customer', 'rental']

    # Extract each table
    for table_name in tables_to_extract:
        print(f"Extracting {table_name}...")

        # Extract data
        df = loader.extract_table(table_name)

        # Write to Bronze storage (parquet + json)
        paths = loader.write_bronze(
            df,
            source_system="pagila_prod",
            table_name=table_name,
            formats=["parquet", "json"]
        )

        print(f"  Wrote {len(df)} records")
        print(f"  Parquet: {paths['parquet']}")
        print(f"  JSON: {paths['json']}")

    print("Bronze ingestion complete!")

if __name__ == "__main__":
    run_bronze_ingestion()
```

## Advanced Features

### Using Reference Table Pattern

The framework provides mixins for common patterns:

```python
from sqlmodel_framework.base.models import ReferenceTable

class CountryReference(SQLModel, ReferenceTable, table=True):
    """Reference data with automatic audit columns"""
    __tablename__ = "ref_country"

    country_code: str = Field(primary_key=True, max_length=2)
    country_name: str
    region: str

    # ReferenceTable adds:
    # - created_at: datetime
    # - created_by: str
    # - modified_at: datetime
    # - modified_by: str
    # - is_active: bool
```

### Working with Transactional Tables

```python
from sqlmodel_framework.base.models import TransactionalTable

class OrderTransaction(SQLModel, TransactionalTable, table=True):
    """Transactional data with audit trail"""
    __tablename__ = "trx_order"

    order_id: int = Field(primary_key=True)
    customer_id: int
    order_date: datetime
    total_amount: float

    # TransactionalTable adds full audit columns
```

### Container-Based Testing

```python
from sqlmodel_framework.engines import PostgresEngine

def test_bronze_tables():
    """Test Bronze tables with container"""

    # Spin up test container
    engine = PostgresEngine.create_container_engine(
        database="test_bronze",
        port=5433
    )

    # Deploy Bronze tables
    SQLModel.metadata.create_all(engine)

    # Run tests
    with Session(engine) as session:
        film = FilmBronze(
            film_id=1,
            title="Test Film",
            rental_duration=7,
            rental_rate=2.99,
            replacement_cost=19.99
        )
        session.add(film)
        session.commit()

    # Cleanup happens automatically
```

## Testing Your Datakit

### Unit Testing with SQLite

```python
# tests/test_models.py
from sqlmodel_framework.engines import SQLiteEngine
from sqlmodel import Session
import pytest

def test_bronze_metadata():
    """Test Bronze metadata is added correctly"""

    # Use in-memory SQLite for speed
    engine = SQLiteEngine.create_memory_engine()
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        film = FilmBronze(
            film_id=1,
            title="Test Film",
            rental_duration=7,
            rental_rate=2.99,
            replacement_cost=19.99,
            # Bronze metadata
            bronze_source_system="test",
            bronze_source_table="film"
        )
        session.add(film)
        session.commit()

        # Verify metadata
        retrieved = session.get(FilmBronze, 1)
        assert retrieved.bronze_source_system == "test"
        assert retrieved.bronze_load_timestamp is not None
```

### Integration Testing with Containers

```python
# tests/test_pipeline.py
def test_full_pipeline():
    """Test complete Bronze ingestion"""

    # Setup test database
    config = PostgresConfig(
        host="localhost",
        port=5433,
        database="test_pagila",
        username="postgres",
        password="postgres"
    )

    connector = PostgresConnector(config)
    loader = PagilaBronzeLoader(
        connector,
        bronze_path=Path("/tmp/test_bronze")
    )

    # Run extraction
    df = loader.extract_table("film", limit=10)

    # Verify Bronze metadata
    assert "bronze_load_timestamp" in df.columns
    assert "bronze_source_system" in df.columns
    assert len(df) == 10
```

## Next Steps

### 1. Explore More Examples
- [Simple PostgreSQL Bronze](examples/simple_postgres_bronze/) - Minimal Bronze implementation
- [Kerberos Authentication](examples/kerberos_bronze/) - Production auth setup
- [Multi-Source Bronze](examples/multi_source_bronze/) - Combining multiple databases

### 2. Read the API Reference
- [API_REFERENCE.md](API_REFERENCE.md) - Complete documentation of all classes and methods
- [Framework README](README.md) - Architecture and design principles

### 3. Learn Patterns
- [SQLModel Patterns](../docs/patterns/sqlmodel-patterns.md) - Data engineering patterns
- [Runtime Patterns](../docs/patterns/runtime-patterns.md) - Environment isolation

### 4. Build Your Datakit
1. Start with the framework base classes
2. Extend only what you need to customize
3. Use the testing utilities for validation
4. Deploy with confidence!

## Common Pitfalls to Avoid

❌ **DON'T** rebuild what the framework provides
❌ **DON'T** create custom metadata fields - use BronzeMetadata
❌ **DON'T** implement your own connection pooling
❌ **DON'T** write Kerberos auth code - it's built in

✅ **DO** extend framework base classes
✅ **DO** use provided mixins for common patterns
✅ **DO** leverage test utilities for validation
✅ **DO** follow framework conventions

## Getting Help

- **Framework Issues**: [GitHub Issues](https://github.com/Troubladore/airflow-data-platform/issues)
- **Examples**: Check the [examples/](examples/) directory
- **API Questions**: See [API_REFERENCE.md](API_REFERENCE.md)

---

**Remember**: The framework exists so you don't have to solve already-solved problems. Use it!