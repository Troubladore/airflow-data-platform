# Airflow Data Platform

A modern data platform framework built on Airflow, SQLModel, and containerized infrastructure.

## 🚀 Quick Start

**New to the platform?** → **[Getting Started Guide](docs/)**

**Setting up for development or testing?** → **[Platform Setup](docs/getting-started.md)**

## 📖 Documentation

- **[docs/](docs/)** - Complete documentation and guides
- **[Getting Started](docs/getting-started.md)** - Platform prerequisites and setup
- **[Technical Reference](docs/technical-reference.md)** - Framework APIs and architecture
- **[Security](docs/SECURITY-RISK-ACCEPTANCE.md)** - Security model and risk management

## 🏗️ Architecture Overview

This repository contains the **platform framework**. For business implementations and examples, see [airflow-data-platform-examples](https://github.com/Troubladore/airflow-data-platform-examples).

### Platform Components

- **SQLModel Framework** - Table mixins, schema management, deployment utilities
- **Layer 1 Platform** - Docker infrastructure, databases, networking
- **Layer 2 Datakits** - Generic data processing patterns (dbt, postgres, spark, sqlserver)
- **Layer 3 Warehouses** - Data warehouse deployment patterns

### Platform as Dependency

This platform is designed to be **imported, not forked**:

```toml
# In your business implementation
[dependencies]
sqlmodel-framework = {git = "https://github.com/Troubladore/airflow-data-platform.git", branch = "main", subdirectory = "data-platform/sqlmodel-workspace/sqlmodel-framework"}
```

## 🧪 Development Workflow

1. **Prerequisites** - Follow [Getting Started](docs/getting-started.md) to set up your environment
2. **Framework Development** - Modify `data-platform/sqlmodel-workspace/sqlmodel-framework/`
3. **Testing** - Run framework tests with `uv run pytest`
4. **Integration** - Test with example implementations

## 🤝 Contributing

- **Framework improvements** - Enhance core platform capabilities
- **Documentation** - Keep guides synchronized with code changes
- **Infrastructure** - Improve deployment and development experience

See [CLAUDE.md](CLAUDE.md) for development patterns and git workflows.

## 📋 Current Status

- ✅ SQLModel framework with table mixins and deployment utilities
- ✅ Multi-database support (SQLite, PostgreSQL, SQL Server)
- ✅ Container-based development environment
- ✅ Comprehensive test suite and CI/CD automation
- 🚧 Layer 2 data processing patterns (in development)
- 🚧 Layer 3 warehouse deployment patterns (planned)

---

**Questions?** Check the [documentation](docs/) or create an issue for support.
