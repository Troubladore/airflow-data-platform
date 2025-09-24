# Airflow Data Platform

A modern data platform framework that provides table mixins, schema management, and deployment utilities for data engineering teams. Built on SQLModel with containerized infrastructure for local development and testing.

This repository contains the **platform framework**. For business implementations and examples, see [airflow-data-platform-examples](https://github.com/Troubladore/airflow-data-platform-examples).

## 🚀 Quick Start

**New to the platform?** → **[Learn About This Platform](docs/technical-reference.md)**

**Ready to set up your environment?** → **[Platform Setup](docs/getting-started.md)**

## 📖 Documentation

- **[docs/](docs/)** - Complete documentation and guides
- **[Platform Setup](docs/getting-started.md)** - Environment setup and prerequisites
- **[Technical Reference](docs/technical-reference.md)** - Framework architecture and APIs
- **[Security](docs/SECURITY-RISK-ACCEPTANCE.md)** - Security model and risk management

## 🤝 Contributing

- **Framework improvements** - Enhance core platform capabilities
- **Documentation** - Keep guides synchronized with code changes
- **Infrastructure** - Improve deployment and development experience

See [CLAUDE.md](CLAUDE.md) for development patterns and git workflows.

## 📋 Current Status

- ✅ **Apache Airflow** platform with HTTPS and authentication
- ✅ **Component-based deployment** - 6 atomic, idempotent Ansible components
- ✅ **SQLModel framework** with table mixins and deployment utilities
- ✅ **Multi-database support** (SQLite, PostgreSQL, SQL Server)
- ✅ **Docker Registry** with UI for private image management
- ✅ **Traefik proxy** with automatic HTTPS for all services
- ✅ **mkcert certificates** - Valid HTTPS without browser warnings
- ✅ **Comprehensive test suite** and CI/CD automation

---

**Questions?** Check the [documentation](docs/) or create an issue for support.
