# Detailed Features

This document contains the detailed information about what the platform provides, how to use it, and its structure.

## 🎯 What We Provide

### 1. **SQLModel Framework** - Define Once, Deploy Many
Enables shared data models across business units:
```python
from sqlmodel_framework import ReferenceTable, deploy_data_objects

class Customer(ReferenceTable):
    """Same model deployed to unit-specific warehouses"""
    customer_id: str
    name: str
    email: str
    # Auto-adds: created_at, updated_at, audit columns

# Deploy to any business unit's warehouse
deploy_data_objects([Customer], target="business_unit_a")
deploy_data_objects([Customer], target="business_unit_b")
```
→ [Learn more about SQLModel Framework](../data-platform/sqlmodel-workspace/sqlmodel-framework/README.md)

### 2. **Runtime Environments** - Team Autonomy
Enable teams to use their tools without conflicts:
```python
# Analytics team uses pandas 1.5, ML team uses pandas 2.0
# Each business unit can have different requirements

# Business Unit A - Analytics focus
analytics_transform = DockerOperator(
    image='runtime-environments/python-transform:unit-a-analytics',
    # Their specific pandas, statsmodels, etc.
)

# Business Unit B - ML focus
ml_transform = DockerOperator(
    image='runtime-environments/python-transform:unit-b-ml',
    # Their specific pytorch, tensorflow, etc.
)
```
→ [Learn more about Runtime Environments](../runtime-environments/README.md)

### 3. **Simple Developer Tools**
Registry caching and Kerberos ticket sharing without complexity:
```bash
cd platform-bootstrap
make start  # That's it - registry cache + ticket sharing running
```
→ [Learn more about Platform Bootstrap](../platform-bootstrap/README.md)

## 🚀 Quick Start (10 minutes)

### Prerequisites
```bash
# You probably already have these
docker --version     # Docker Desktop or Engine
astro version       # Astronomer CLI
python3 --version   # Python 3.8+
```

### Setup
```bash
# 1. Clone this repository
git clone https://github.com/Troubladore/airflow-data-platform.git
cd airflow-data-platform

# 2. Start minimal platform services
cd platform-bootstrap
make start  # Starts registry cache + ticket sharer

# 3. Create your Astronomer project
cd ~/projects
astro dev init my-project

# 4. Add our frameworks (optional)
cd my-project
# Add to requirements.txt:
# sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@main#subdirectory=data-platform/sqlmodel-workspace/sqlmodel-framework

# 5. Start Airflow
astro dev start
```

Your Airflow is now running at http://localhost:8080 with our enterprise enhancements available!

## 🏗️ Repository Structure

```
airflow-data-platform/
├── sqlmodel-framework/        # Core data engineering framework
│   ├── src/                  # Reusable patterns
│   └── tests/                # Comprehensive test suite
│
├── runtime-environments/      # Dependency isolation containers
│   ├── base-images/          # Standard transformation environments
│   └── patterns/             # Usage patterns and examples
│
├── platform-bootstrap/        # Developer environment setup
│   ├── registry-cache.yml    # Offline development support
│   ├── ticket-sharer.yml     # Kerberos ticket sharing
│   └── Makefile              # Simple commands
│
└── docs/                     # Layered documentation
    ├── getting-started-simple.md
    ├── patterns/             # How to use effectively
    └── reference/            # Detailed specifications
```

→ **[See complete directory structure](directory-structure.md)** for full repository organization

## 🤔 What This Is NOT

- ❌ **Not a platform** - Astronomer is the platform
- ❌ **Not a replacement** - We enhance, not replace
- ❌ **Not complex** - If it's complex, we're doing it wrong
- ❌ **Not required** - Astronomer works fine without us

## ✅ What This IS

- ✅ **Patterns** - Proven enterprise patterns for data engineering
- ✅ **Tools** - Simple tools that solve real problems
- ✅ **Frameworks** - Reusable code for common tasks
- ✅ **Thin layer** - Minimal overhead on top of Astronomer
