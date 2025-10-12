# Airflow Data Platform - Technical Documentation

This directory contains **technical documentation** for the Airflow Data Platform framework and infrastructure components.

## 🎯 Audience & Purpose

This documentation is for:
- **Framework contributors** - Building platform components
- **Infrastructure engineers** - Deploying and operating the platform
- **Advanced users** - Deep customization and extension

**For learning and business implementation**, visit the [examples repository](https://github.com/Troubladore/airflow-data-platform-examples).

## 📚 Documentation Structure

### **Core Architecture**
- **[TECHNICAL-ARCHITECTURE.md](TECHNICAL-ARCHITECTURE.md)** - Framework internals, API reference, deployment patterns
- **[WHY-THIS-ARCHITECTURE.md](WHY-THIS-ARCHITECTURE.md)** - Design decisions, trade-offs, technical rationale
- **[ECOSYSTEM-OVERVIEW.md](ECOSYSTEM-OVERVIEW.md)** - Component relationships, technical integration points

### **Security & Operations**
- **[SECURITY-RISK-ACCEPTANCE.md](SECURITY-RISK-ACCEPTANCE.md)** - Security model, threat analysis, risk management

## 🔧 Framework Components

### **SQLModel Framework**
- **Location**: `sqlmodel-framework/`
- **Purpose**: Table mixins, deployment utilities, schema management
- **Installation**: UV dependency via git+https

```python
# Import platform components
from sqlmodel_framework.base.models import TransactionalTableMixin, ReferenceTableMixin
from sqlmodel_framework.utils.deployment import deploy_datakit
```

### **Execution Engines**
- **Location**: `layer2-datakits/` (dbt-runner, postgres-runner, spark-runner, sqlserver-runner)
- **Purpose**: Generic data processing and orchestration patterns
- **Extension**: Copy and modify for business-specific needs

### **Infrastructure**
- **Location**: `layer1-platform/`
- **Purpose**: Docker configurations, test infrastructure, database utilities
- **Usage**: Local development and CI/CD automation

## 🏗️ Platform as Dependency Architecture

The platform is designed to be **imported, not forked**:

```toml
# Business implementations reference platform via UV dependency
[dependencies]
sqlmodel-framework = {git = "https://github.com/Troubladore/airflow-data-platform.git", branch = "main", subdirectory = "sqlmodel-framework"}
```

**Technical Benefits**:
- **Controlled API surface** - Stable interfaces for business code
- **Independent versioning** - Platform evolves without breaking consumers
- **Dependency injection** - Business logic plugs into framework patterns
- **Testing isolation** - Framework and business tests run independently

## 🧩 Extension Points

### **Custom Table Mixins**
```python
from sqlmodel_framework.base.models import BaseMixin
from sqlmodel import Field
from datetime import datetime

class CustomAuditMixin(BaseMixin):
    """Business-specific audit patterns."""
    audit_user: str = Field(nullable=False)
    audit_timestamp: datetime = Field(default_factory=datetime.utcnow)
```

### **Custom Deployment Targets**
```python
from sqlmodel_framework.engines import BaseEngine

class CustomDatabaseEngine(BaseEngine):
    """Custom database deployment logic."""
    def create_tables(self, metadata):
        # Your database-specific deployment logic
        pass
```

### **Custom Execution Engines**
```python
# Pattern: Copy existing engine as template
# Example: layer2-datakits/postgres-runner/ → your-custom-runner/
# Modify for your specific execution patterns
```

## 🔬 Development Workflow

### **Framework Development**
1. **Modify core** - Update `sqlmodel-framework/`
2. **Run tests** - Execute framework test suite with `uv run pytest`
3. **Version bump** - Update version for breaking API changes
4. **Integration test** - Validate with example implementations

### **Infrastructure Changes**
1. **Update Docker** - Modify `layer1-platform/docker/` configurations
2. **Update automation** - Modify `scripts/` for new functionality
3. **Test CI/CD** - Ensure automation works with changes

## 📊 Performance & Scalability

### **Framework Optimization**
- **SQLModel performance** - Table creation and query generation efficiency
- **Schema management** - Large-scale multi-database deployment patterns
- **Memory efficiency** - Framework memory footprint optimization

### **Infrastructure Scaling**
- **Container orchestration** - Docker deployment and scaling patterns
- **Database performance** - Connection pooling and query optimization
- **Monitoring integration** - Observability and alerting infrastructure

## 🚀 Progressive Learning Path

### **For Platform Developers**
1. **[WHY-THIS-ARCHITECTURE.md](WHY-THIS-ARCHITECTURE.md)** - Understand design rationale
2. **[TECHNICAL-ARCHITECTURE.md](TECHNICAL-ARCHITECTURE.md)** - Deep dive into implementation
3. **Framework source code** - Explore `sqlmodel-framework/`

### **For Infrastructure Engineers**
1. **[ECOSYSTEM-OVERVIEW.md](ECOSYSTEM-OVERVIEW.md)** - Component relationships
2. **[SECURITY-RISK-ACCEPTANCE.md](SECURITY-RISK-ACCEPTANCE.md)** - Security model
3. **Infrastructure code** - Explore `layer1-platform/` and `scripts/`

### **For Advanced Users**
1. **[Examples repository](https://github.com/Troubladore/airflow-data-platform-examples)** - See working patterns
2. **Extension points** - Build custom components using framework APIs
3. **Performance tuning** - Optimize for your specific use cases

## 🤝 Contributing

- **Framework improvements** - Enhance core platform capabilities
- **Documentation updates** - Keep technical docs synchronized with code
- **Performance optimizations** - Improve scalability and efficiency
- **Security enhancements** - Strengthen platform security model

---

**Remember**: This is the **technical documentation**. For tutorials, getting started guides, and business implementation patterns, visit the [examples repository](https://github.com/Troubladore/airflow-data-platform-examples).
