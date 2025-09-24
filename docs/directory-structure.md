# Directory Structure

Complete overview of the repository organization and the purpose of each directory.

## 📁 Repository Root

```
airflow-data-platform/
├── data-platform/                 # SQLModel framework core
├── runtime-environments/          # Isolated execution containers
├── platform-bootstrap/            # Developer environment setup
├── deprecated/                    # Components being phased out
├── docs/                          # Documentation
├── ansible/                       # Infrastructure automation (being simplified)
├── scripts/                       # Utility scripts
├── prerequisites/                 # Setup requirements
└── ref/                          # Reference implementations
```

## 🔷 Core Platform Components

### `data-platform/sqlmodel-workspace/sqlmodel-framework/`
**Purpose**: Core data engineering framework built on SQLModel

```
sqlmodel-framework/
├── src/
│   └── sqlmodel_framework/
│       ├── core/                 # Core framework functionality
│       │   ├── base.py          # Base classes and mixins
│       │   ├── table_mixins.py  # Reusable table patterns
│       │   └── trigger_builder.py # Automatic trigger generation
│       ├── deployment/           # Deployment utilities
│       │   └── deploy.py        # Database object deployment
│       └── utils/               # Helper utilities
├── tests/                        # Comprehensive test suite
│   ├── unit/                    # Unit tests
│   └── integration/             # Integration tests
└── docs/                        # Framework documentation
```

### `runtime-environments/`
**Purpose**: Containerized environments for dependency isolation

```
runtime-environments/
├── base-images/                  # Standard base containers
│   ├── python-transform/        # Python data transformation base
│   │   ├── Dockerfile
│   │   └── requirements-base.txt
│   ├── pyspark-transform/       # PySpark processing base
│   └── dbt-transform/           # dbt execution base
├── templates/                    # Templates for new environments
│   └── create-runtime.sh        # Script to generate new runtime
└── patterns/                    # Usage patterns and examples
    ├── version-management.md
    └── dependency-isolation.md
```

### `platform-bootstrap/`
**Purpose**: Minimal developer environment setup

```
platform-bootstrap/
├── registry-cache.yml            # Local Docker registry for offline work
├── ticket-sharer.yml            # Simple Kerberos ticket sharing
├── setup-scripts/               # Environment setup utilities
│   ├── doctor.sh               # Diagnose environment issues
│   └── configure-environment.sh # Initial configuration
├── Makefile                     # Simple command interface
└── README.md                   # Bootstrap documentation
```

## 📚 Documentation

### `docs/`
**Purpose**: Layered documentation following drill-down pattern

```
docs/
├── getting-started-simple.md    # Quick start guide (10 minutes)
├── directory-structure.md       # This file
├── patterns/                    # How-to guides
│   ├── sqlmodel-patterns.md   # SQLModel usage patterns
│   ├── runtime-patterns.md    # Container isolation patterns
│   └── migration-patterns.md  # Migration strategies
├── reference/                   # Detailed specifications
│   ├── configuration.md       # All configuration options
│   ├── api.md                 # API documentation
│   └── troubleshooting.md    # Common issues
└── archive/                    # Outdated documentation
    └── [old complex docs]      # Kept for reference only
```

## 🔧 Supporting Infrastructure

### `ansible/`
**Purpose**: Automation for complex setups (being simplified)

```
ansible/
├── inventory/                   # Environment definitions
├── components/                  # Atomic, idempotent tasks
├── orchestrators/              # Task coordination
└── group_vars/                 # Configuration variables
```

**Note**: Being simplified as we move to Astronomer-native patterns

### `scripts/`
**Purpose**: Utility scripts for development and deployment

```
scripts/
├── install-pipx-deps.sh        # Development dependencies
├── deploy_datakit.py           # Deploy datakit to database
├── test-with-postgres-sandbox.sh # PostgreSQL testing
└── validate-*.sh               # Various validation scripts
```

## 🗄️ Deprecated Components

### `deprecated/`
**Purpose**: Components being removed in alignment with Astronomer

```
deprecated/
├── layer1-platform/            # Astronomer provides platform layer
├── kerberos-astronomer/        # Over-engineered, replaced with simple sharing
└── README.md                  # Explains deprecation rationale
```

## 🔄 Components Pending Migration

These will move to `airflow-data-platform-examples`:

```
layer2-dbt-projects/            # → examples/dbt-patterns/
layer3-warehouses/              # → examples/warehouse-patterns/
```

## 📦 Prerequisites

### `prerequisites/`
**Purpose**: Required setup components

```
prerequisites/
├── certificates/               # mkcert certificate management
└── traefik-registry/          # Being removed (see issue #14)
```

## 📖 Reference Materials

### `ref/`
**Purpose**: Reference implementations and examples

```
ref/
├── docs/                      # Additional documentation
├── jupyter-exploratory/       # Experimental notebooks
└── layer3-warehouse/         # Warehouse patterns (moving to examples)
```

## 🎯 Key Files at Root

- `README.md` - Main entry point (being updated)
- `README-NEW.md` - Updated vision-aligned documentation
- `CLAUDE.md` - Development guidelines and patterns
- `MIGRATION_PLAN.md` - Repository restructuring plan
- `pyproject.toml` - Python project configuration
- `.gitignore` - Git ignore rules
- `.pre-commit-config.yaml` - Code quality automation

## 📝 Documentation Files (Root)

Migration and planning documents at root:
- `MIGRATE_TO_EXAMPLES.md` - Components moving to examples repo
- `PHASE1_COMPLETE.md` - Migration status tracking
- `DATAKITS_STAY_HERE.md` - Rationale for runtime-environments
- `DOCUMENTATION_AUDIT.md` - Documentation improvement plan

## 🔍 Finding What You Need

| If you're looking for... | Look in... |
|-------------------------|------------|
| SQLModel table patterns | `data-platform/sqlmodel-workspace/sqlmodel-framework/` |
| Container base images | `runtime-environments/base-images/` |
| Developer setup | `platform-bootstrap/` |
| Documentation | `docs/` |
| Utility scripts | `scripts/` |
| Deprecated code | `deprecated/` |
| Examples | [airflow-data-platform-examples](https://github.com/Troubladore/airflow-data-platform-examples) repo |

## 🚀 Quick Navigation

- **Start here**: [README.md](../README.md)
- **Get started**: [docs/getting-started-simple.md](getting-started-simple.md)
- **Core framework**: [data-platform/sqlmodel-workspace/sqlmodel-framework/README.md](../data-platform/sqlmodel-workspace/sqlmodel-framework/README.md)
- **Developer tools**: [platform-bootstrap/README.md](../platform-bootstrap/README.md)

---

*This structure reflects the simplified, Astronomer-aligned architecture where we provide thin, valuable enhancements rather than a complete platform replacement.*
