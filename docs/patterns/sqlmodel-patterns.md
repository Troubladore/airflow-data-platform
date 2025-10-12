# SQLModel Patterns for Data Engineering

**Read time: 3 minutes**

How to use SQLModel for consistent, enterprise-ready data models.

## 🎯 The Problem

Every data team reinvents:
- Audit columns (created_at, updated_at)
- Soft deletes
- Trigger management
- Schema deployment

Our SQLModel framework provides these patterns once, correctly.

## 🏗️ Core Concepts

### Table Types

We provide **2 table patterns** for different data needs:

1. **ReferenceTable** - For slowly-changing dimension data (customers, products)
2. **TransactionalTable** - For high-volume events (orders, measurements)

### What You Get Automatically

Both table types include:
- ✅ Audit columns (created_at, updated_at, systime)
- ✅ Database triggers for timestamp updates
- ✅ Deployment utilities
- ✅ Type safety and validation

## 📦 Reference Tables

For master data that changes slowly:

```python
from sqlmodel_framework import ReferenceTable
from sqlmodel import Field
from typing import Optional

class Customer(ReferenceTable, table=True):
    __tablename__ = "customers"

    # Your business columns
    customer_id: str = Field(primary_key=True)
    name: str
    email: str
    phone: Optional[str] = None

    # These are added automatically:
    # - created_at: datetime
    # - updated_at: datetime
    # - inactivated_date: Optional[datetime] (soft delete)
    # - systime: datetime
```

**Use for**: Customers, products, locations, employees

## 📊 Transactional Tables

For high-volume event data:

```python
from sqlmodel_framework import TransactionalTable
from sqlmodel import Field
from datetime import datetime

class Order(TransactionalTable, table=True):
    __tablename__ = "orders"

    # Your business columns
    order_id: int = Field(primary_key=True)
    customer_id: str
    order_date: datetime
    total_amount: float

    # These are added automatically:
    # - created_at: datetime
    # - updated_at: datetime
    # - systime: datetime
```

**Use for**: Orders, events, measurements, logs

## 🚀 How to Use

### Step 1: Define Your Model

```python
# models/bronze_tables.py
from sqlmodel_framework import ReferenceTable, TransactionalTable

class Product(ReferenceTable, table=True):
    __tablename__ = "products"

    product_id: str = Field(primary_key=True)
    name: str
    category: str
    price: float

class Sale(TransactionalTable, table=True):
    __tablename__ = "sales"

    sale_id: int = Field(primary_key=True)
    product_id: str
    quantity: int
    sale_date: datetime
```

### Step 2: Deploy to Database

```python
from sqlmodel_framework import deploy_data_objects
from models.bronze_tables import Product, Sale

# Deploy tables with triggers
deploy_data_objects(
    table_classes=[Product, Sale],
    target="postgres_local"  # or "sqlite_memory" for testing
)
```

### Step 3: Use in Your Pipeline

```python
from sqlmodel import Session, select
from models.bronze_tables import Product

# Standard SQLModel operations work
with Session(engine) as session:
    # Insert
    product = Product(
        product_id="P001",
        name="Widget",
        category="Tools",
        price=29.99
    )
    session.add(product)
    session.commit()

    # created_at and updated_at are set automatically!
```

## 🎯 Key Benefits

1. **No more copy-paste** - Audit columns defined once
2. **Consistent patterns** - Every team uses the same approach
3. **Database agnostic** - Works with PostgreSQL, MySQL, SQLite, SQL Server
4. **Type safe** - Catch errors before runtime
5. **Deploy anywhere** - Same models in dev, test, prod

## 📖 Learn More

### Quick Starts
- [Your First SQLModel Table](sqlmodel-first-table.md) - 5 min tutorial
- [Deploying to Production](sqlmodel-deployment.md) - Database setup

### Deep Dives
- [Custom Table Mixins](sqlmodel-custom-mixins.md) - Create your own patterns
- [Trigger Management](sqlmodel-triggers.md) - How automatic triggers work
- [Migration Strategies](sqlmodel-migrations.md) - Schema evolution

### Examples
See working examples in the [examples repository](https://github.com/Troubladore/airflow-data-platform-examples):
- [pagila-sqlmodel-basic/](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/pagila-implementations/pagila-sqlmodel-basic) - Complete implementation

## 🚨 Common Questions

**Q: Can I add custom columns to the base tables?**
A: Yes! Add any columns you need. The framework only adds the audit columns.

**Q: What about relationships between tables?**
A: Standard SQLModel relationships work perfectly. See [examples](sqlmodel-relationships.md).

**Q: How do I migrate existing tables?**
A: See our [migration guide](sqlmodel-migrations.md) for step-by-step instructions.

---

**Next**: [Create Your First Table](sqlmodel-first-table.md) (5 minutes)
