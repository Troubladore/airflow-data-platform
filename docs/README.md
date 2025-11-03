# Airflow Data Platform - Documentation

Welcome to the documentation hub for the Airflow Data Platform. This platform provides enterprise patterns and framework components on top of Astronomer for data engineering teams.

## 🎯 Progressive Discovery - Start Here

### Level 1: What Is This? (Overview)
- **[Main README](../README.md)** - Platform overview and philosophy
- **[Platform Setup Guide](getting-started-simple.md)** - Deploy the platform with Astronomer

### Level 2: How Do I Use It? (Getting Started)
- **[Framework Getting Started](../sqlmodel-framework/GETTING_STARTED.md)** - Build your first datakit
- **[Framework Examples](../sqlmodel-framework/examples/)** - Working code examples
- **[Hello World Example](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-world)** - Simplest Airflow example

### Level 3: Why Does It Work This Way? (Patterns & Concepts)
- **[SQLModel Patterns](patterns/sqlmodel-patterns.md)** - Data engineering patterns with SQLModel
- **[Runtime Patterns](patterns/runtime-patterns.md)** - Team isolation and dependency management
- **[Directory Structure](directory-structure.md)** - Repository organization

### Level 4: How Do I Customize It? (Reference & Advanced)
- **[Framework API Reference](../sqlmodel-framework/API_REFERENCE.md)** - Complete class and method documentation
- **[Framework Architecture](../sqlmodel-framework/README.md)** - Technical architecture details
- **[Kerberos Setup for WSL2](kerberos-setup-wsl2.md)** - Enterprise authentication

## 🚀 Quick Start Paths

### For Data Engineers Building Datakits
1. Read [Framework Getting Started](../sqlmodel-framework/GETTING_STARTED.md)
2. Review [Simple PostgreSQL Example](../sqlmodel-framework/examples/simple_postgres_bronze/)
3. Check [API Reference](../sqlmodel-framework/API_REFERENCE.md) for specific needs

### For Platform Administrators
1. Follow [Platform Setup Guide](getting-started-simple.md)
2. Review [Runtime Patterns](patterns/runtime-patterns.md)
3. Configure services as needed

### For Teams Using Kerberos/SQL Server
1. Follow [Kerberos Wizard Experience](kerberos-wizard-experience.md) for guided setup
2. Setup [Kerberos for WSL2](kerberos-setup-wsl2.md) for manual configuration
3. Use [Kerberos Progressive Validation](kerberos-progressive-validation.md) for troubleshooting
4. Review [Kerberos Bronze Example](../sqlmodel-framework/examples/kerberos_bronze/)
5. Deploy Kerberos sidecar service

## 📚 Documentation Structure

```
docs/
├── README.md                      # This file - documentation hub
├── getting-started-simple.md      # Platform setup with Astronomer
├── patterns/                      # Design patterns and best practices
│   ├── sqlmodel-patterns.md      # Data engineering patterns
│   └── runtime-patterns.md       # Dependency isolation
├── directory-structure.md         # Repository organization
├── kerberos-setup-wsl2.md        # Enterprise auth setup
└── archive/                       # Historical docs (deprecated)

sqlmodel-framework/
├── GETTING_STARTED.md            # Framework quick start guide
├── API_REFERENCE.md              # Complete API documentation
├── README.md                     # Framework architecture
└── examples/                     # Working examples
    ├── simple_postgres_bronze/   # Basic Bronze extraction
    └── kerberos_bronze/         # Enterprise auth example
```

## 🏗️ Key Platform Components

### SQLModel Framework
The core framework providing:
- **Database Connectors** - PostgreSQL, SQL Server with Kerberos
- **Table Mixins** - BronzeMetadata, ReferenceTable, TransactionalTable
- **Data Pipelines** - BronzeIngestionPipeline base classes
- **Testing Utilities** - Multi-database deployment and validation

[Learn more →](../sqlmodel-framework/README.md)

### Optional Services
- **OpenMetadata** - Data catalog and discovery
- **Kerberos Sidecar** - Enterprise authentication
- **Pagila Database** - PostgreSQL sample data

[Service setup →](getting-started-simple.md)

## 🎨 Documentation Philosophy

### Integrative with Progressive Discovery
- **High-level concepts** float to the top (overviews, philosophies)
- **Implementation details** available when needed (API references)
- **Clear navigation paths** for different user journeys
- **No redundancy** - each concept documented once, referenced many

### Current and Actionable
- All examples are tested and working
- Documentation reflects the latest architecture
- Deprecated content clearly marked and archived
- Links are validated and functional

## 🔄 Recent Updates

- ✅ Added comprehensive Framework documentation (GETTING_STARTED.md, API_REFERENCE.md)
- ✅ Created working examples with PostgreSQL and Kerberos
- ✅ Updated main README with Framework Quick Reference
- ✅ Consolidated redundant documentation
- ✅ Improved progressive discovery navigation

## 🤝 Contributing to Documentation

When updating documentation:
1. **Follow progressive discovery** - Overview → Getting Started → Patterns → Reference
2. **Avoid redundancy** - Link to existing docs rather than duplicating
3. **Test all examples** - Ensure code samples actually work
4. **Update navigation** - Keep this README's links current
5. **Archive outdated content** - Move to `archive/` with deprecation notice

---

**Need help?** Check the documentation path above that matches your use case, or open an issue on GitHub.