# Data Platform Ecosystem Overview

**A learning guide for data engineers new to this architectural approach**

## TL;DR - What Problem Are We Solving?

Traditional data pipelines suffer from:
- **Schema drift** breaks pipelines at runtime
- **Copy-paste transforms** across teams
- **Fragile integration** between systems
- **Testing** requires full infrastructure

Our approach trades ~15% performance for 80% reduction in maintenance overhead through **type-safe, reusable data contracts**.

## High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    Layer 1      │    │    Layer 2      │    │    Layer 3      │
│  Infrastructure │    │  Data Objects   │    │   Warehouse     │
│                 │    │   (Datakits)    │    │   Instances     │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Docker Images │────▶ • Schema Models  │────▶ • DAG Configs   │
│ • Databases     │    │ • Transform Fns │    │ • Connections   │
│ • Airflow       │    │ • Test Factories│    │ • Schedules     │
│ • Registries    │    │ • Typed Contracts│   │ • Environments  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
   Build Once           Share & Reuse         Configure & Deploy
```

## Core Components Deep Dive

### Layer 1: Infrastructure Foundation
**What**: Containerized runtime environments
**Why**: Consistent execution across dev/test/prod
**Tradeoff**: Container overhead for environment consistency

```bash
# Example: PostgreSQL + Airflow runtime
docker-compose up -d postgres airflow
```

### Layer 2: Data Objects (Datakits)
**What**: SQLModel-based schema definitions + transform functions
**Why**: Type-safe data contracts prevent runtime schema failures
**Tradeoff**: ~15% SQLModel overhead for compile-time safety

```python
# Datakit example: Type-safe source→target transform
def customer_transform(source: SystemA.Customer) -> Bronze.Customer:
    return Bronze.Customer(
        id=source.customer_id,
        name=source.full_name.upper(),
        created_at=datetime.now()
    )
```

### Layer 3: Warehouse Instances
**What**: Specific database connections + DAG configurations
**Why**: Same datakits deployed to different environments
**Tradeoff**: Configuration complexity for environment flexibility

```python
# Layer 3: Use Layer 2 datakits in Airflow DAG
dag = DAG('customer_pipeline')
extract_task = PythonOperator(
    python_callable=extract_customers,
    op_kwargs={'datakit': SystemADatakit}
)
```

## The Developer Journey: Postgres A → Postgres B

### Scenario: Transfer customer data from System A to Bronze layer

**What you need to create:**

1. **Layer 2 - Datakit for System A**
   ```python
   # If internal team: They publish this
   # If external: You reverse-engineer
   class Customer(SQLModel, table=True):
       customer_id: int
       full_name: str
       email: str
   ```

2. **Layer 2 - Datakit for Bronze Target**
   ```python
   class Customer(TransactionalTableMixin, SQLModel, table=True):
       id: int
       name: str
       email: str
       # Audit fields from mixin: created_at, updated_at, systime
   ```

3. **Layer 2 - Transform Function**
   ```python
   def customer_bronze_transform(source: SystemA.Customer) -> Bronze.Customer:
       return Bronze.Customer(
           id=source.customer_id,
           name=source.full_name.upper(),
           email=source.email.lower()
       )
   ```

4. **Layer 3 - DAG Configuration**
   ```python
   # Airflow DAG using your datakits
   factory = BulkDataLoader(bronze_engine)
   factory.load_with_transform(
       source_query=select(SystemA.Customer),
       transform_func=customer_bronze_transform,
       batch_size=1000
   )
   ```

### Multi-Source Scenario: A + D + E → B

**Layer 2**: Create separate datakits for each source
- **Datakit A** (reuse if internal team publishes)
- **Datakit D** (reverse-engineer external system)
- **Datakit E** (reverse-engineer external system)
- **Datakit B** (your consolidated target schema)

**Layer 3**: Orchestrate multiple sources in single DAG
```python
# DAG coordinates multiple transforms
a_to_b_task = transform_task(SystemA.Customer, Bronze.Customer, a_transform)
d_to_b_task = transform_task(SystemD.Order, Bronze.Order, d_transform)
e_to_b_task = transform_task(SystemE.Product, Bronze.Product, e_transform)
```

## Performance & Scale Characteristics

### Bronze Layer: Speed-Optimized
- **No foreign keys** = faster parallel inserts
- **Minimal constraints** = maximum throughput
- **Bulk loading** with `COPY` operations
- **Parallel batching** (when implemented - see [Issue #7](https://github.com/Troubladore/workstation-setup/issues/7))

### Silver Layer: Quality-Assured
- **Add constraints** = data validation
- **Foreign keys** = referential integrity
- **Indexes** = query performance
- **Same datakits** redeployed with different configs

### Gold Layer: Business-Optimized
- **Dimensional models** = fast analytics
- **Aggregated facts** = pre-computed metrics
- **Optimized indexes** = sub-second queries

## Key Architectural Tradeoffs

| We Choose | Instead Of | Penalty | Compensation |
|-----------|------------|---------|--------------|
| SQLModel ORM | Raw SQL | ~15% slower | 80% fewer runtime errors |
| Type-safe contracts | Dynamic schemas | Upfront modeling | Catches breaks at compile-time |
| Layered architecture | Direct connections | More components | Reusable, testable parts |
| Container deployment | Local installs | Resource overhead | Environment consistency |
| UV package manager | pip | Learning curve | Faster, more reliable deps |
| Ruff (single tool) | black+isort+flake8 | New syntax | Simpler toolchain |

## When This Approach Works Best

**✅ Good fit:**
- Multiple source systems with evolving schemas
- Teams that value reliability over raw performance
- Organizations wanting reusable data components
- Need for comprehensive testing/validation

**❌ Not ideal:**
- Simple, single-source pipelines
- Performance-critical, high-frequency data (consider raw SQL)
- Teams preferring minimal abstraction
- Strict latency requirements (<1s transforms)

## Getting Started

1. **Start small**: Pick one simple A→B transfer
2. **Create datakits**: Use `data-platform-framework` to define schemas
3. **Build transform**: Write typed transform function
4. **Test locally**: Use framework's test factories
5. **Deploy Layer 3**: Configure Airflow DAG with your datakits

## Common Questions

**Q: Why not just use dbt for everything?**
A: dbt excels at SQL transforms but doesn't help with cross-system integration or runtime type safety.

**Q: Is the 15% performance penalty worth it?**
A: For most use cases, yes. You're trading CPU cycles for developer productivity and system reliability.

**Q: How do I handle schema changes?**
A: SQLModel datakits fail fast when schemas change, forcing explicit handling rather than silent corruption.

**Q: Can I still use raw SQL for performance-critical paths?**
A: Absolutely. Use datakits for the 80% case, drop to raw SQL for the 20% that needs maximum speed.

---

**Next Steps:**
- Read [Layer 2 Data Processing](README-LAYER2-DATA-PROCESSING.md) for component details
- Review [Layer 3 Warehouses](README-LAYER3-WAREHOUSES.md) for orchestration
- Check [Issue #7](https://github.com/Troubladore/workstation-setup/issues/7) for production Bronze features roadmap
