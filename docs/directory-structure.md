# Directory Structure

Clean, focused repository organization with only core platform components.

## 📁 Repository Root

```
airflow-data-platform/
├── sqlmodel-framework/            # Core data engineering framework
├── runtime-environments/          # Isolated execution containers
├── platform-bootstrap/            # Developer environment setup
├── platform-infrastructure/       # Base platform services (postgres, etc.)
├── wizard/                        # Interactive configuration system
├── scripts/                       # Utility scripts
├── tests/                        # Test suite
├── docs/                          # Documentation
└── deprecated/                    # Archived components (not detailed here)
```

## 🏛️ Architecture Layers

The platform is organized into two complementary layers that work together:

### Interactive Configuration Layer (`wizard/`)
The wizard provides an interactive, declarative configuration system for platform services. Each service has its own wizard module with:
- **spec.yaml**: Declarative YAML specification defining configuration steps, prompts, and conditional logic
- **actions.py**: Python implementation of configuration actions
- **tests/**: Comprehensive test coverage for wizard behavior

The wizard layer sits on top of the infrastructure layer, providing a user-friendly interface for configuring platform services.

### Platform Infrastructure Layer (`platform-infrastructure/`)
The infrastructure layer contains docker-compose orchestration and configuration for base platform services:
- **PostgreSQL**: Core database service for platform metadata and application data
- **Test Containers**: Lightweight database client containers for connectivity testing
- **Future Services**: Additional base platform services as needed

The wizard configures this infrastructure layer by generating environment files, docker-compose configurations, and service-specific settings.

**Why This Separation Exists:**
- **Configurability**: Users can customize platform services through the wizard without editing infrastructure code
- **Modularity**: Services can be added/removed independently
- **Testability**: Each layer can be tested in isolation
- **Clarity**: Clear separation between "what to configure" (wizard specs) and "what gets configured" (infrastructure)

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

### `platform-infrastructure/`
**Purpose**: Base platform services orchestration and configuration

```
platform-infrastructure/
├── docker-compose.yml          # Base platform services orchestration
├── Makefile                   # Build and deployment targets
├── README.md                  # Infrastructure documentation
├── postgres/                  # PostgreSQL service configuration
│   ├── Dockerfile            # PostgreSQL with Kerberos + SSL support
│   ├── initdb.d/             # Database initialization scripts
│   └── config/               # PostgreSQL configuration files
└── test-containers/           # Database client test containers
    ├── postgres-test/         # PostgreSQL client container
    │   └── Dockerfile        # PostgreSQL client with Kerberos + ODBC
    └── sqlcmd-test/          # SQL Server client container
        └── Dockerfile        # FreeTDS sqlcmd with Kerberos + ODBC
```

**Key Services:**
- **PostgreSQL**: Core database service with Kerberos authentication and SSL encryption support
- **Test Containers**: Lightweight database client containers for testing connectivity and authentication

**How It Differs from runtime-environments/:**
- `platform-infrastructure/`: Base platform services (databases, message queues, etc.)
- `runtime-environments/`: Execution environments for data processing workloads (dbt, Spark, etc.)

#### `test-containers/` - Database Client Test Containers

**Purpose**: Lightweight database client containers for testing connectivity, authentication, and ODBC drivers.

**Design Principles:**
- **Minimal footprint**: Alpine-based images for fast builds and small size
- **Security-first**: Non-root users, minimal packages, explicit dependencies
- **Corporate-friendly**: Support for custom base images and corporate CA certificates
- **Flexible configuration**: Build from source or use prebuilt images from corporate registries

**Available Containers:**

**postgres-test** - PostgreSQL Client Container
- Base: Alpine Linux
- Tools: `psql` (PostgreSQL client), `kinit` (Kerberos), `isql` (ODBC testing)
- Drivers: PostgreSQL ODBC driver, unixODBC
- Auth: Kerberos ticket cache support, SSL certificate validation
- User: Non-root `testuser` (UID 1001)

**sqlcmd-test** - SQL Server Client Container
- Base: Alpine Linux
- Tools: `sqlcmd` (via FreeTDS), `kinit` (Kerberos), `isql` (ODBC testing)
- Drivers: FreeTDS (SQL Server ODBC), unixODBC
- Auth: Kerberos ticket cache support, SSL certificate validation
- User: Non-root `testuser` (UID 1001)

**Configuration via Wizard:**
Each test container supports two build modes:
- **Build mode** (`PREBUILT=false`): Build from Dockerfile using configurable base image
  - `IMAGE_POSTGRES_TEST`: Base image for postgres-test (default: `alpine:3.20`)
  - `IMAGE_SQLCMD_TEST`: Base image for sqlcmd-test (default: `alpine:3.20`)
- **Prebuilt mode** (`PREBUILT=true`): Use prebuilt image from corporate registry
  - `POSTGRES_TEST_PREBUILT=true`: Use `IMAGE_POSTGRES_TEST` as-is
  - `SQLCMD_TEST_PREBUILT=true`: Use `IMAGE_SQLCMD_TEST` as-is

**Use Cases:**
- Test PostgreSQL/SQL Server connectivity before deploying workloads
- Validate Kerberos authentication configuration
- Debug ODBC driver setup and DSN configuration
- Verify SSL certificate trust chains
- Interactive database exploration and ad-hoc queries

### `wizard/`
**Purpose**: Interactive configuration system for platform services

```
wizard/
├── engine/                    # Wizard execution engine (spec interpreter)
│   ├── core.py               # Core wizard orchestration
│   ├── state.py              # State management
│   └── prompts.py            # Interactive prompt handling
├── flows/                     # Reusable wizard flows
│   ├── docker_image_flow.py  # Docker image configuration flow
│   └── network_flow.py       # Network configuration flow
├── services/                  # Service-specific wizard modules
│   ├── base_platform/        # Base platform service wizard
│   │   ├── spec.yaml         # Main wizard specification
│   │   ├── actions.py        # Wizard actions implementation
│   │   ├── discovery.py      # Service discovery logic
│   │   └── tests/           # Comprehensive test suite
│   ├── kerberos/             # Kerberos service wizard
│   │   ├── spec.yaml
│   │   ├── actions.py
│   │   └── tests/
│   ├── pagila/               # Pagila demo wizard
│   │   ├── spec.yaml
│   │   └── actions.py
│   └── openmetadata/         # OpenMetadata wizard
│       ├── spec.yaml
│       └── actions.py
├── utils/                    # Wizard utilities
│   ├── docker_utils.py       # Docker helper functions
│   └── file_utils.py         # File manipulation utilities
└── tests/                    # Wizard engine tests
    └── test_engine.py        # Engine unit tests
```

**How Wizards Work:**

1. **Declarative Specifications** (`spec.yaml`):
   - Define configuration steps and prompts
   - Conditional logic based on user choices
   - State management and validation rules
   - Template rendering for configuration files

2. **Action Implementations** (`actions.py`):
   - Python functions that implement configuration logic
   - Generate docker-compose files, environment files, configs
   - Interact with Docker, file system, external services
   - Validate user input and system state

3. **Testing Strategy**:
   - Each service has comprehensive test coverage
   - Tests validate wizard logic, state management, file generation
   - Integration tests verify end-to-end configuration flows

**Example: base_platform Wizard**
- Configures PostgreSQL service (custom image, Kerberos, SSL)
- Configures test containers (postgres-test, sqlcmd-test)
- Generates `.env` file with user choices
- Generates `docker-compose.yml` with service definitions
- Validates configuration before applying

## 🔧 Supporting Infrastructure

### `scripts/`
**Purpose**: Utility scripts for development and deployment

```
scripts/
├── test-with-postgres-sandbox.sh    # PostgreSQL sandbox for testing
├── install-pipx-deps.sh             # Development dependencies setup
├── scan-supply-chain.sh             # Security vulnerability scanning
└── run-tests.sh                     # Test runner for framework
```

### `tests/` (Note: Currently in sqlmodel-framework/tests/)
**Purpose**: Test infrastructure lives within each component

- SQLModel framework tests: `sqlmodel-framework/tests/`
- Runtime environment tests: Within each `runtime-environments/*/tests/`
- Platform bootstrap tests: `platform-bootstrap/tests/` (if needed)

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
- `platform-config.yaml.example` - Template for platform configuration (used by `./platform setup`)
- `pyproject.toml` - Repository-level Python configuration
- `.gitignore` - Git ignore rules
- `.pre-commit-config.yaml` - Code quality automation
- `.security-exceptions.yml` - Security scan exceptions

## 🔍 Finding What You Need

| If you're looking for... | Look in... |
|-------------------------|------------|
| Base platform services | `platform-infrastructure/` |
| Container base images | `runtime-environments/` |
| Developer setup | `platform-bootstrap/` |
| Documentation | `docs/` |
| Interactive platform setup | `wizard/` |
| SQLModel table patterns | `sqlmodel-framework/` |
| Test containers | `platform-infrastructure/test-containers/` |
| Utility scripts | `scripts/` |

## 🚀 Quick Navigation

- **Start here**: [README.md](../README.md)
- **Get started**: [docs/getting-started-simple.md](getting-started-simple.md)
- **Core framework**: [sqlmodel-framework/](../sqlmodel-framework/)
- **Platform services**: [platform-infrastructure/README.md](../platform-infrastructure/README.md)
- **Interactive setup**: [wizard/](../wizard/)
- **Developer tools**: [platform-bootstrap/README.md](../platform-bootstrap/README.md)

## 📝 Note on deprecated/

The `deprecated/` folder contains archived components that are being phased out or migrated. We don't detail its structure here as it's not part of the active platform. See [deprecated/README.md](../deprecated/README.md) for what's archived there.

---

*This structure reflects the simplified, Astronomer-aligned architecture where we provide thin, valuable enhancements rather than a complete platform replacement.*
