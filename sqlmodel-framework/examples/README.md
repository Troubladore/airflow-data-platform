# SQLModel Framework Examples

This directory contains working examples that demonstrate how to use the SQLModel Framework for building data engineering pipelines. Each example is self-contained and focuses on specific framework features.

## Available Examples

### 1. [Simple PostgreSQL Bronze](simple_postgres_bronze/)

**What it demonstrates:**
- Basic Bronze layer extraction from PostgreSQL
- Using framework connectors instead of raw psycopg2
- Leveraging BronzeMetadata mixin for standard fields
- Writing to parquet and JSON formats

**Best for:** Getting started with the framework, understanding core concepts

**Run it:**
```bash
cd simple_postgres_bronze
uv sync
python extract.py
```

---

### 2. [Kerberos Bronze](kerberos_bronze/)

**What it demonstrates:**
- Enterprise authentication with Kerberos/GSSAPI
- Password-free database connections
- Handling container authentication issues
- Production-grade security patterns

**Best for:** Enterprise deployments, secure environments

**Run it:**
```bash
cd kerberos_bronze
kinit username@REALM.COM  # Get Kerberos ticket first
uv sync
python extract_with_kerberos.py
```

---

## Coming Soon

### Multi-Source Bronze
- Combining data from multiple databases
- Handling different authentication methods
- Parallel extraction strategies

### Silver Layer Transform
- Using framework for Silver layer transformations
- Data quality validation
- Incremental processing patterns

### Testing Patterns
- Unit testing with SQLite
- Integration testing with containers
- Mocking strategies for pipelines

## Running the Examples

### Prerequisites

All examples require:
1. Python 3.9 or higher
2. `uv` package manager (`pip install uv`)
3. Access to a PostgreSQL database (local or remote)

Some examples have additional requirements:
- **Kerberos example**: Valid Kerberos environment and ticket
- **Multi-source**: Access to multiple databases

### General Setup

Each example follows the same pattern:

1. **Install dependencies:**
   ```bash
   cd example_name
   uv sync
   ```

2. **Configure environment:**
   ```bash
   # Create .env file or export variables
   export DB_HOST=localhost
   export DB_PORT=5432
   export DB_NAME=your_database
   export DB_USER=your_user
   export DB_PASSWORD=your_password
   ```

3. **Run the example:**
   ```bash
   python script_name.py
   ```

## Learning Path

If you're new to the framework, we recommend this order:

1. **Start here** → [Simple PostgreSQL Bronze](simple_postgres_bronze/)
   - Learn the basics without complexity

2. **Add security** → [Kerberos Bronze](kerberos_bronze/)
   - Understand enterprise authentication

3. **Read the docs**:
   - [Getting Started Guide](../GETTING_STARTED.md)
   - [API Reference](../API_REFERENCE.md)

4. **Build your own**:
   - Use examples as templates
   - Extend framework base classes
   - Follow the patterns

## Key Concepts Demonstrated

### Don't Rebuild the Framework

Every example shows why you should use framework components:

```python
# ❌ Don't do this
import psycopg2
conn = psycopg2.connect(...)  # Manual everything

# ✅ Do this
from sqlmodel_framework.base.connectors import PostgresConnector
connector = PostgresConnector(config)  # Framework handles complexity
```

### Use Provided Mixins

The framework provides mixins for common patterns:

```python
# ❌ Don't manually define metadata fields
class MyTable(SQLModel, table=True):
    id: int
    created_at: datetime  # Manual
    created_by: str       # Manual
    # ... lots of boilerplate

# ✅ Use framework mixins
class MyTable(SQLModel, BronzeMetadata, table=True):
    id: int
    # Metadata fields added automatically!
```

### Extend Base Classes

Build on top of framework foundations:

```python
class MyPipeline(BronzeIngestionPipeline):
    """Custom pipeline extending framework base"""

    def extract_table(self, table_name: str) -> pd.DataFrame:
        # Your custom extraction logic
        # Framework handles metadata, storage, validation
```

## Contributing Examples

Have a great example to share? We welcome contributions!

1. Create a new directory: `examples/your_example_name/`
2. Include:
   - `README.md` - Explain what it demonstrates
   - `pyproject.toml` - Dependencies
   - Python scripts - Working code
   - `.env.example` - Environment template

3. Follow patterns from existing examples
4. Submit a pull request

## Troubleshooting

### Common Issues

**"ModuleNotFoundError: No module named 'sqlmodel_framework'"**
- Run `uv sync` to install the framework
- Check your `pyproject.toml` includes the framework dependency

**"Connection refused" errors**
- Verify database is running
- Check host/port configuration
- Ensure network connectivity

**"Authentication failed"**
- For standard auth: Check username/password
- For Kerberos: Run `klist` to verify ticket

### Getting Help

- Check example-specific README files
- Review [API Reference](../API_REFERENCE.md)
- Open an issue on GitHub

## License

All examples are provided under the same license as the main framework. Use them freely as templates for your own projects!