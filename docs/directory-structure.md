# Directory Structure

Clean, focused repository organization with only core platform components.

## 📁 Repository Root

```
airflow-data-platform/
├── sqlmodel-framework/            # Core data engineering framework
├── runtime-environments/          # Isolated execution containers
├── platform-bootstrap/            # Developer environment setup
├── scripts/                       # Utility scripts
├── tests/                        # Test suite
├── docs/                          # Documentation
└── deprecated/                    # Archived components (not detailed here)
```

## 🔷 Core Platform Components

### `sqlmodel-framework/`
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
├── scripts/                     # Deployment and utility scripts
├── pyproject.toml              # Package configuration
└── README.md                   # Framework documentation
```

### `runtime-environments/`
**Purpose**: Containerized environments for dependency isolation

```
runtime-environments/
├── base-images/                  # Standard base containers (future)
├── dbt-runner/                   # dbt execution environment
├── postgres-runner/              # PostgreSQL data processing
├── spark-runner/                # Spark processing environment
├── sqlserver-runner/            # SQL Server data processing
└── README.md                    # Documentation
```

### `platform-bootstrap/`
**Purpose**: Minimal developer environment setup

```
platform-bootstrap/
├── developer-kerberos-simple.yml     # Simple Kerberos ticket sharing
├── developer-kerberos-standalone.yml # Standalone Kerberos service
├── local-registry-cache.yml          # Local Docker registry for offline work
├── setup-scripts/                    # Environment setup utilities
│   └── doctor.sh                    # Diagnose environment issues
├── config/                          # Configuration files
├── Makefile                         # Simple command interface
└── README.md                        # Bootstrap documentation
```

## 🔧 Supporting Infrastructure

### `scripts/`
**Purpose**: Utility scripts for development and deployment

```
scripts/
├── deploy_datakit.py                 # Deploy datakit to database
├── test-with-postgres-sandbox.sh    # PostgreSQL testing
├── install-pipx-deps.sh            # Development dependencies
└── scan-supply-chain.sh            # Security scanning
```

### `tests/`
**Purpose**: Repository-level test infrastructure

```
tests/
├── unit/                            # Unit tests
├── integration/                     # Integration tests
└── fixtures/                        # Test fixtures and data
```

### `docs/`
**Purpose**: Comprehensive documentation

```
docs/
├── getting-started-simple.md       # Quick start guide
├── kerberos-setup-wsl2.md         # Kerberos configuration guide
├── directory-structure.md         # This file
├── detailed-features.md           # Detailed feature documentation
├── patterns/                      # Usage patterns
│   ├── sqlmodel-patterns.md      # SQLModel usage patterns
│   └── runtime-patterns.md       # Container isolation patterns
├── working-notes/                 # Development notes and decisions
├── archive/                       # Outdated documentation
├── CLAUDE.md                      # Development guidelines
└── SECURITY.md                    # Security documentation
```

## 🎯 Key Files at Root

- `README.md` - Main entry point
- `pyproject.toml` - Repository-level Python configuration
- `.gitignore` - Git ignore rules
- `.pre-commit-config.yaml` - Code quality automation
- `.security-exceptions.yml` - Security scan exceptions

## 🔍 Finding What You Need

| If you're looking for... | Look in... |
|-------------------------|------------|
| SQLModel table patterns | `sqlmodel-framework/` |
| Container base images | `runtime-environments/` |
| Developer setup | `platform-bootstrap/` |
| Documentation | `docs/` |
| Utility scripts | `scripts/` |

## 🚀 Quick Navigation

- **Start here**: [README.md](../README.md)
- **Get started**: [docs/getting-started-simple.md](getting-started-simple.md)
- **Core framework**: [sqlmodel-framework/](../sqlmodel-framework/)
- **Developer tools**: [platform-bootstrap/README.md](../platform-bootstrap/README.md)

## 📝 Note on deprecated/

The `deprecated/` folder contains archived components that are being phased out or migrated. We don't detail its structure here as it's not part of the active platform. See [deprecated/README.md](../deprecated/README.md) for what's archived there.

---

*This structure reflects the simplified, Astronomer-aligned architecture where we provide thin, valuable enhancements rather than a complete platform replacement.*
