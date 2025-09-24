# SQLModel Patterns for Data Engineering

Enterprise-ready patterns using our SQLModel framework for consistent, scalable data modeling.

## 🎯 Why SQLModel?

SQLModel combines the best of SQLAlchemy (powerful) and Pydantic (modern Python types) for data engineering:

- **Type safety** - Catch errors at development time
- **Automatic validation** - Data integrity by default
- **ORM and schemas** - One model, multiple uses
- **Modern Python** - Clean, readable code

## 🏗️ Core Patterns

### 1. Reference Tables

For slowly-changing dimension data (customers, products, locations):

```python
from sqlmodel_framework import ReferenceTable
from datetime import datetime
from typing import Optional

class Customer(ReferenceTable):
    """Customer master data with automatic audit columns"""

    # Business columns
    customer_id: str = Field(primary_key=True)
    name: str
    email: str
    phone: Optional[str] = None

    # Audit columns added automatically by ReferenceTable:
    # - created_at: datetime
    # - updated_at: datetime
    # - systime: datetime
    # - inactivated_date: Optional[datetime]
```

**What you get automatically**:
- Audit columns (created_at, updated_at, systime)
- Soft delete support (inactivated_date)
- Automatic triggers for timestamp updates
- Deployment utilities

### 2. Transactional Tables

For high-volume transactional data (orders, events, measurements):

```python
from sqlmodel_framework import TransactionalTable
from decimal import Decimal

class SalesOrder(TransactionalTable):
    """Sales orders with transaction tracking"""

    # Business columns
    order_id: str = Field(primary_key=True)
    customer_id: str = Field(foreign_key="customer.customer_id")
    order_amount: Decimal
    order_date: datetime

    # TransactionalTable adds:
    # - systime: datetime (when loaded to warehouse)
    # - created_at: datetime (when record created)
    # - updated_at: datetime (when record last modified)
```

**Transactional vs Reference**:
- **Reference**: Master data, updates in place, soft deletes
- **Transactional**: Event data, immutable, hard deletes OK

### 3. Type-Safe Configurations

Define your data models with strong typing:

```python
from sqlmodel import Field
from enum import Enum
from typing import Literal

class OrderStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    SHIPPED = "shipped"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"

class Order(TransactionalTable):
    order_id: str = Field(primary_key=True)

    # Type-safe enums
    status: OrderStatus = OrderStatus.PENDING

    # Literal types for constrained values
    priority: Literal["low", "medium", "high"] = "medium"

    # Precise decimal handling for money
    amount: Decimal = Field(decimal_places=2)
```

## 🚀 Deployment Patterns

### 1. Simple Database Deployment

```python
from sqlmodel_framework import deploy_data_objects
from sqlmodel import create_engine

# Define your models
class Customer(ReferenceTable):
    customer_id: str = Field(primary_key=True)
    name: str
    email: str

class Order(TransactionalTable):
    order_id: str = Field(primary_key=True)
    customer_id: str = Field(foreign_key="customer.customer_id")
    amount: Decimal

# Deploy to database
engine = create_engine("sqlite:///my_warehouse.db")
table_classes = [Customer, Order]

deploy_data_objects(table_classes, engine)
# ✅ Tables created with proper indexes, constraints, and triggers
```

### 2. Multi-Environment Deployment

```python
import os
from sqlmodel_framework import deploy_data_objects, create_target_config

# Environment-aware configuration
env = os.getenv('ENV', 'dev')
config = create_target_config(env)

if env == 'dev':
    # SQLite for development
    config.database_url = "sqlite:///dev_warehouse.db"
elif env == 'qa':
    # PostgreSQL for QA
    config.database_url = f"postgresql://user:pass@qa-db:5432/warehouse"
elif env == 'prod':
    # SQL Server for production
    config.database_url = f"mssql://prod-server/warehouse?trusted_connection=yes"

deploy_data_objects(table_classes, config)
```

### 3. Airflow DAG Integration

```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def deploy_warehouse_schema():
    """Deploy our data models to the warehouse"""
    from my_models import Customer, Order, Product
    from sqlmodel_framework import deploy_data_objects, get_target_config

    # Get environment-specific config
    config = get_target_config(env='prod')
    table_classes = [Customer, Order, Product]

    # Deploy with validation
    deploy_data_objects(table_classes, config, validate=True)
    return "Schema deployed successfully"

# DAG definition
dag = DAG(
    'deploy_warehouse_schema',
    description='Deploy data warehouse schema',
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
)

deploy_task = PythonOperator(
    task_id='deploy_schema',
    python_callable=deploy_warehouse_schema,
    dag=dag,
)
```

## 🔧 Advanced Patterns

### 1. Custom Field Behaviors

```python
from sqlmodel import Field, Column
from sqlalchemy import String, text

class Product(ReferenceTable):
    product_id: str = Field(primary_key=True)

    # Custom validation
    name: str = Field(min_length=1, max_length=100)

    # Database-level defaults
    status: str = Field(
        sa_column=Column(String(20), server_default=text("'active'"))
    )

    # Computed columns (PostgreSQL example)
    search_vector: Optional[str] = Field(
        sa_column=Column("search_vector", String,
                        server_default=text("to_tsvector('english', name)"))
    )
```

### 2. Relationship Modeling

```python
from sqlmodel import Relationship
from typing import List, Optional

class Customer(ReferenceTable):
    customer_id: str = Field(primary_key=True)
    name: str

    # One-to-many relationship
    orders: List["Order"] = Relationship(back_populates="customer")

class Order(TransactionalTable):
    order_id: str = Field(primary_key=True)
    customer_id: str = Field(foreign_key="customer.customer_id")
    amount: Decimal

    # Many-to-one relationship
    customer: Optional[Customer] = Relationship(back_populates="orders")

    # Many-to-many through junction table
    products: List["Product"] = Relationship(
        back_populates="orders",
        link_table="order_product"
    )
```

### 3. Data Quality Patterns

```python
from pydantic import validator, root_validator

class Customer(ReferenceTable):
    customer_id: str = Field(primary_key=True)
    email: str
    phone: Optional[str] = None

    # Field validation
    @validator('email')
    def email_must_be_valid(cls, v):
        assert '@' in v, 'Email must contain @'
        return v.lower()

    # Cross-field validation
    @root_validator
    def must_have_contact_method(cls, values):
        email, phone = values.get('email'), values.get('phone')
        if not email and not phone:
            raise ValueError('Must provide email or phone')
        return values
```

## 📊 Testing Patterns

### 1. Model Testing

```python
import pytest
from sqlmodel import Session, create_engine
from sqlmodel_framework import deploy_data_objects

@pytest.fixture
def test_db():
    """Create test database"""
    engine = create_engine("sqlite:///:memory:")
    deploy_data_objects([Customer, Order], engine)
    return engine

def test_customer_creation(test_db):
    """Test basic model functionality"""
    with Session(test_db) as session:
        customer = Customer(
            customer_id="CUST001",
            name="Test Customer",
            email="test@example.com"
        )
        session.add(customer)
        session.commit()

        # Verify audit columns are set
        assert customer.created_at is not None
        assert customer.systime is not None
```

### 2. Validation Testing

```python
def test_customer_validation():
    """Test Pydantic validation"""
    # Valid customer
    customer = Customer(
        customer_id="CUST001",
        name="Valid Customer",
        email="valid@example.com"
    )

    # Invalid email should raise ValidationError
    with pytest.raises(ValidationError):
        Customer(
            customer_id="CUST002",
            name="Invalid Customer",
            email="not-an-email"
        )
```

## 🎯 Best Practices

### 1. Naming Conventions

```python
# Tables: Singular, PascalCase
class Customer(ReferenceTable):
    pass

class SalesOrder(TransactionalTable):  # Not "sales_orders"
    pass

# Columns: snake_case
class Product(ReferenceTable):
    product_id: str
    product_name: str
    unit_price: Decimal
    created_at: datetime  # Added automatically
```

### 2. Primary Key Strategies

```python
# Business keys for reference data
class Customer(ReferenceTable):
    customer_id: str = Field(primary_key=True)  # Business meaningful

# UUIDs for transactional data
import uuid
from sqlmodel import Field

class Order(TransactionalTable):
    order_id: uuid.UUID = Field(primary_key=True, default_factory=uuid.uuid4)
```

### 3. Environment Configuration

```python
# config/database.py
import os
from dataclasses import dataclass

@dataclass
class DatabaseConfig:
    url: str
    echo: bool = False
    pool_size: int = 5

def get_db_config() -> DatabaseConfig:
    env = os.getenv('ENV', 'dev')

    if env == 'dev':
        return DatabaseConfig(
            url="sqlite:///dev.db",
            echo=True
        )
    elif env == 'prod':
        return DatabaseConfig(
            url=os.getenv('DATABASE_URL'),
            pool_size=20
        )
```

## 🚨 Common Gotchas

### 1. Field() vs Column() server_default

```python
# ❌ Wrong - Field doesn't accept server_default
active: bool = Field(default=True, server_default=text("true"))

# ✅ Correct - server_default goes in sa_column
active: bool = Field(
    sa_column=Column(Boolean, server_default=text("true")),
    default=True
)
```

### 2. Relationship Loading

```python
# Be explicit about loading strategies
class Order(TransactionalTable):
    customer: Optional[Customer] = Relationship(
        back_populates="orders",
        sa_relationship_kwargs={"lazy": "select"}  # vs "joined", "subquery"
    )
```

### 3. Decimal vs Float for Money

```python
from decimal import Decimal

# ✅ Correct for money
amount: Decimal = Field(decimal_places=2)

# ❌ Wrong - floating point precision issues
amount: float  # Don't use for currency!
```

## 📚 Real-World Example

Complete example for an e-commerce domain:

```python
from sqlmodel_framework import ReferenceTable, TransactionalTable
from sqlmodel import Field, Relationship
from decimal import Decimal
from datetime import datetime
from typing import Optional, List
from enum import Enum

class CustomerStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"

class Customer(ReferenceTable, table=True):
    customer_id: str = Field(primary_key=True)
    name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=1, max_length=255)
    status: CustomerStatus = CustomerStatus.ACTIVE

    orders: List["Order"] = Relationship(back_populates="customer")

class OrderStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    SHIPPED = "shipped"
    DELIVERED = "delivered"

class Order(TransactionalTable, table=True):
    order_id: str = Field(primary_key=True)
    customer_id: str = Field(foreign_key="customer.customer_id")
    total_amount: Decimal = Field(decimal_places=2)
    status: OrderStatus = OrderStatus.PENDING
    order_date: datetime

    customer: Optional[Customer] = Relationship(back_populates="orders")
    line_items: List["OrderLineItem"] = Relationship(back_populates="order")

class Product(ReferenceTable, table=True):
    product_id: str = Field(primary_key=True)
    name: str
    price: Decimal = Field(decimal_places=2)
    category: str

class OrderLineItem(TransactionalTable, table=True):
    line_id: str = Field(primary_key=True)
    order_id: str = Field(foreign_key="order.order_id")
    product_id: str = Field(foreign_key="product.product_id")
    quantity: int
    unit_price: Decimal = Field(decimal_places=2)

    order: Optional[Order] = Relationship(back_populates="line_items")
```

This gives you a production-ready data model with audit trails, type safety, and deployment utilities - all the enterprise patterns you need without the complexity!

---

**Next**: See [Runtime Environment Patterns](runtime-patterns.md) to learn how to isolate your transformations from Airflow dependencies.
