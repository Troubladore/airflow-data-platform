# Directory Structure Documentation Gaps

**Date:** 2025-11-01
**Task:** 7a (RED phase) - Identify gaps in directory-structure.md
**Purpose:** Document what's missing from directory-structure.md before adding comprehensive documentation

---

## Overview

The current `docs/directory-structure.md` file provides a good overview of the core platform components (sqlmodel-framework, runtime-environments, platform-bootstrap) but is missing critical architecture documentation and key platform directories that exist in the repository.

## Missing Sections

### 1. Architecture Layers Explanation (Critical Gap)

**What's Missing:**
- No explanation of the two-layer architecture:
  - **wizard/** - Interactive configuration and setup layer
  - **platform-infrastructure/** - Core platform services and infrastructure

**Why It Matters:**
- Users need to understand the separation of concerns between interactive setup (wizard) and platform services (infrastructure)
- This is fundamental to understanding how the platform is organized and how components relate to each other
- The wizard layer sits on top of and configures the infrastructure layer

**Where It Should Go:**
- Should be added as a new top-level section: "## Architecture Layers"
- Should come immediately after "## Repository Root" and before "## Core Platform Components"
- Should explain the relationship between wizard and platform-infrastructure

**Content Needed:**
- Explanation of wizard layer (interactive configuration, service specs, actions)
- Explanation of platform-infrastructure layer (docker-compose services, configuration)
- How they interact (wizard configures infrastructure)
- Why this separation exists (configurability, modularity)

---

### 2. platform-infrastructure/ Section (Major Gap)

**What's Missing:**
- No documentation of the `platform-infrastructure/` directory at all
- This directory exists in the repository but is completely absent from directory-structure.md

**Current State in Repository:**
```
platform-infrastructure/
├── docker-compose.yml          # Base platform services orchestration
├── .env.example               # Environment configuration template
├── Makefile                   # Build and deployment targets
├── README.md                  # Infrastructure documentation
├── postgres/                  # PostgreSQL service configuration
└── test-containers/           # Test container Dockerfiles (to be added)
    ├── postgres-test/         # PostgreSQL client test container
    └── sqlcmd-test/          # SQL Server client test container
```

**Why It Matters:**
- platform-infrastructure/ is a core part of the base platform refactor (Phase 1 completed)
- Houses all docker-compose service definitions for base platform
- Central location for infrastructure-as-code
- Will include test containers (Phase 2 - current work)

**Where It Should Go:**
- Should be added as a new subsection under "## Core Platform Components"
- Should come after platform-bootstrap/ and before "## Supporting Infrastructure"
- Should be at the same level as sqlmodel-framework/ and runtime-environments/

**Content Needed:**
- Purpose: Base platform services orchestration and configuration
- Structure showing docker-compose.yml, Makefile, postgres/, test-containers/
- Explanation of what base platform services are (postgres, future additions)
- How it differs from runtime-environments/ (platform services vs execution environments)

---

### 3. platform-infrastructure/test-containers/ Subsection (Specific Gap)

**What's Missing:**
- No documentation of test-containers/ directory (being added in Phase 2)
- No explanation of test container purpose and architecture

**What Will Exist:**
```
platform-infrastructure/test-containers/
├── postgres-test/
│   └── Dockerfile            # PostgreSQL client with Kerberos + ODBC
└── sqlcmd-test/
    └── Dockerfile            # SQL Server client with FreeTDS + ODBC
```

**Why It Matters:**
- Test containers are lightweight client containers for testing database connectivity
- Support both Kerberos authentication and ODBC connections
- Configurable via wizard (prebuilt vs build modes)
- Corporate-friendly (support custom base images)

**Where It Should Go:**
- Should be a subsection under platform-infrastructure/
- Should come after the postgres/ subsection

**Content Needed:**
- Purpose: Lightweight database client containers for testing connectivity
- Two containers: postgres-test (PostgreSQL client) and sqlcmd-test (SQL Server client via FreeTDS)
- Key features: Kerberos support, ODBC drivers, non-root users, configurable base images
- Configuration via wizard: IMAGE_POSTGRES_TEST, POSTGRES_TEST_PREBUILT, etc.
- Build modes: build from Alpine vs prebuilt from corporate registry

---

### 4. wizard/ Section (Major Gap)

**What's Missing:**
- No documentation of the `wizard/` directory at all
- This is a major component of the platform (interactive configuration system)

**Current State in Repository:**
```
wizard/
├── engine/                    # Wizard execution engine (spec interpreter)
├── flows/                     # Reusable wizard flows
├── services/                  # Service-specific wizard modules
│   ├── base_platform/        # Base platform service wizard
│   │   ├── spec.yaml         # Main wizard specification
│   │   ├── actions.py        # Wizard actions
│   │   ├── discovery.py      # Service discovery logic
│   │   └── tests/           # Comprehensive test suite
│   ├── kerberos/             # Kerberos service wizard
│   ├── pagila/               # Pagila demo wizard
│   └── openmetadata/         # OpenMetadata wizard
├── utils/                    # Wizard utilities
└── tests/                    # Wizard engine tests
```

**Why It Matters:**
- The wizard is the primary user interface for platform setup and configuration
- Implements declarative YAML-based configuration specifications
- Each service has its own wizard module with spec, actions, and tests
- Critical for understanding how platform configuration works

**Where It Should Go:**
- Should be added as a new subsection under "## Core Platform Components"
- Should come after platform-infrastructure/ (since wizard configures infrastructure)
- Should be at the same level as sqlmodel-framework/ and runtime-environments/

**Content Needed:**
- Purpose: Interactive configuration system for platform services
- Architecture: spec.yaml (declarative config) + actions.py (implementation) + tests
- Service modules: base_platform, kerberos, pagila, openmetadata
- How specs work: steps, conditional logic, state management
- How actions work: Python functions that implement configuration logic
- Testing strategy: Each service has comprehensive test coverage

---

### 5. Navigation Table Update (Minor Gap)

**What's Missing:**
- Navigation table doesn't include wizard/ or platform-infrastructure/
- Missing entry for test containers

**Current Table:**
```markdown
| If you're looking for... | Look in... |
|-------------------------|------------|
| SQLModel table patterns | `sqlmodel-framework/` |
| Container base images | `runtime-environments/` |
| Developer setup | `platform-bootstrap/` |
| Documentation | `docs/` |
| Utility scripts | `scripts/` |
```

**What Should Be Added:**
```markdown
| Interactive platform setup | `wizard/` |
| Base platform services | `platform-infrastructure/` |
| Test containers | `platform-infrastructure/test-containers/` |
```

**Why It Matters:**
- Users need quick navigation to these important components
- Improves discoverability

**Where It Should Go:**
- Add new rows to existing "## Finding What You Need" table
- Maintain alphabetical or logical ordering

---

### 6. Quick Navigation Links (Minor Gap)

**What's Missing:**
- No quick links to wizard/ or platform-infrastructure/
- These are major platform components that deserve prominent navigation

**What Should Be Added:**
```markdown
- **Platform services**: [platform-infrastructure/README.md](../platform-infrastructure/README.md)
- **Wizard setup**: [wizard/README.md](../wizard/README.md) (if exists)
```

**Why It Matters:**
- Improves discoverability of major components
- Consistent with existing quick navigation pattern

**Where It Should Go:**
- Add to "## Quick Navigation" section
- Insert after "Core framework" and before closing

---

## Gap Priority Analysis

### P0 - Critical (Must Fix)
1. **Architecture Layers Explanation** - Fundamental to understanding platform organization
2. **platform-infrastructure/ Section** - Core component completely missing

### P1 - High Priority (Should Fix)
3. **wizard/ Section** - Major user-facing component not documented
4. **platform-infrastructure/test-containers/ Subsection** - Directly relevant to Phase 2 work

### P2 - Medium Priority (Nice to Have)
5. **Navigation Table Update** - Improves discoverability
6. **Quick Navigation Links** - Convenience for users

---

## Implementation Approach (Task 7b - GREEN)

When implementing these fixes:

1. **Add Architecture Layers section first** - Provides context for everything else
2. **Add platform-infrastructure/ section** - Major component documentation
3. **Add wizard/ section** - Major component documentation
4. **Add test-containers/ subsection** - Specific to Phase 2 work
5. **Update navigation table** - Quick reference improvement
6. **Update quick navigation** - Convenience links

**Validation:**
- Ensure all directory paths referenced actually exist in repository
- Ensure README.md files mentioned exist (or note if they don't)
- Verify structure matches actual repository layout
- Check that examples are accurate and helpful

---

## Context: Why These Gaps Exist

The current `directory-structure.md` was likely written when the repository had a simpler structure focused on:
- sqlmodel-framework (core data engineering)
- runtime-environments (containerized execution)
- platform-bootstrap (developer setup)

Since then, the platform has evolved significantly:
- **Phase 1 (Completed)**: Base platform refactor - moved postgres service to platform-infrastructure/
- **Phase 2 (In Progress)**: Test container configuration - adding test-containers/ to platform-infrastructure/
- **Wizard Development**: Added comprehensive wizard system for interactive configuration

The documentation simply hasn't kept pace with these architectural improvements.

---

## Success Criteria

After Task 7b (GREEN) completes, directory-structure.md should:
- [ ] Explain the two-layer architecture (wizard + platform-infrastructure)
- [ ] Document platform-infrastructure/ directory with full structure
- [ ] Document test-containers/ subdirectory and its purpose
- [ ] Document wizard/ directory with service modules explained
- [ ] Include wizard/ and platform-infrastructure/ in navigation table
- [ ] Include quick links to major new components
- [ ] Accurately reflect actual repository structure as of 2025-11-01
- [ ] Help new users understand where to find configuration vs infrastructure

---

**Next Action:** Proceed to Task 7b (GREEN) to implement these documentation additions.
