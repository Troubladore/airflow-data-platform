# Simple PostgreSQL Bronze Example

This example demonstrates the minimal code needed to build a Bronze layer datakit using the SQLModel Framework.

## What This Example Shows

- ✅ Using framework connectors instead of raw psycopg2
- ✅ Leveraging BronzeMetadata mixin for standard fields
- ✅ Extending BronzeIngestionPipeline for data extraction
- ✅ Proper connection management with context managers
- ✅ Writing Bronze data to parquet and JSON formats

## Running the Example

### Prerequisites

1. PostgreSQL database with sample data (we use Pagila)
2. Python environment with framework installed

### Setup

```bash
# Install dependencies
uv sync

# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=pagila
export DB_USER=postgres
export DB_PASSWORD=postgres
```

### Run

```bash
python extract.py
```

This will:
1. Connect to the PostgreSQL database
2. Extract data from the film and actor tables
3. Add Bronze metadata (timestamp, source info)
4. Write to `/tmp/bronze/` in both parquet and JSON formats

## Key Concepts

### 1. Don't Rebuild the Framework

Instead of writing your own connection code:
```python
# ❌ Don't do this
import psycopg2
conn = psycopg2.connect(...)
```

Use the framework connector:
```python
# ✅ Do this
from sqlmodel_framework.base.connectors import PostgresConnector
connector = PostgresConnector(config)
```

### 2. Use BronzeMetadata Mixin

Instead of manually defining Bronze fields:
```python
# ❌ Don't do this
class FilmBronze(SQLModel, table=True):
    film_id: int
    bronze_load_timestamp: datetime  # Manual
    bronze_source_system: str        # Manual
    # ... more manual fields
```

Use the mixin:
```python
# ✅ Do this
class FilmBronze(SQLModel, BronzeMetadata, table=True):
    film_id: int
    # Bronze fields automatically added!
```

### 3. Extend the Pipeline Base Class

The `BronzeIngestionPipeline` provides:
- `add_bronze_metadata()` - Adds standard Bronze columns
- `write_bronze()` - Writes to parquet/JSON with proper paths
- `validate_bronze_data()` - Data quality checks

## Files in This Example

- `extract.py` - Main extraction script
- `models.py` - Bronze table definitions
- `pyproject.toml` - Dependencies including framework
- `README.md` - This file

## Next Steps

After understanding this example:
1. Check the [Kerberos example](../kerberos_bronze/) for enterprise auth
2. Read the [API Reference](../../API_REFERENCE.md) for all available features
3. Build your own Bronze datakit!