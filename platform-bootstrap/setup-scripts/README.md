# Platform Setup Scripts

**Purpose:** Modular, idempotent setup scripts for platform components

**Philosophy:** Each script is standalone, focused, and can be run independently or as part of a larger setup flow.

---

## Design Principles

### 1. **Idempotent**
- Safe to run multiple times
- Detects existing configuration
- Skips what's already done
- Only changes what's needed

### 2. **Standalone**
- Each script has one clear purpose
- No dependencies on other setup scripts
- Can be run in any order (respects prerequisites)
- Self-contained with all needed functions

### 3. **Corporate Environment Aware**
- Reads from `.env` for corporate configuration
- Uses `IMAGE_*` variables for Artifactory paths
- Prompts for corporate settings if needed
- Provides defaults for public internet

### 4. **Testable**
- Can run in dry-run mode
- Returns clear exit codes
- Logs actions for debugging
- Validates before making changes

---

## Available Scripts

### `setup-pagila.sh`
**Purpose:** Install pagila PostgreSQL test database

**What it does:**
- Clones pagila from Troubladore/pagila fork
- Starts PostgreSQL container on platform_network
- Loads schema and test data automatically
- Validates database is accessible

**When to run:**
- Need test data for examples
- Want to try OpenMetadata ingestion
- Testing SQLModel patterns

**Idempotency:**
- Detects if pagila directory exists
- Detects if container already running
- Offers to update/restart/skip

**Usage:**
```bash
./setup-scripts/setup-pagila.sh           # Interactive
./setup-scripts/setup-pagila.sh --yes     # Auto-yes to prompts
./setup-scripts/setup-pagila.sh --reset   # Clean and reinstall
```

---

## Pattern: How Setup Scripts Work

### Standard Structure

Every setup script follows this pattern:

```bash
#!/bin/bash
# Setup Script: Component Name
# ============================
# Purpose: One-line description
# Idempotent: Yes
# Prerequisites: List any required setup

set -e

# 1. Source formatting library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLATFORM_DIR/lib/formatting.sh" ]; then
    source "$PLATFORM_DIR/lib/formatting.sh"
fi

# 2. Load .env for corporate configuration
if [ -f "$PLATFORM_DIR/.env" ]; then
    source "$PLATFORM_DIR/.env"
fi

# 3. Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y) AUTO_YES=true; shift ;;
        --reset) RESET=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# 4. Check if already set up
if check_existing_setup; then
    print_info "Component already configured"
    if ! ask_yes_no "Reconfigure?"; then
        exit 0
    fi
fi

# 5. Perform setup
do_setup_steps

# 6. Validate
validate_setup

# 7. Exit with status
print_success "Setup complete!"
exit 0
```

### Corporate Environment Support

**Every setup script should:**

```bash
# Load .env early
if [ -f "$PLATFORM_DIR/.env" ]; then
    source "$PLATFORM_DIR/.env"
fi

# Use IMAGE_* variables with defaults
POSTGRES_IMAGE="${IMAGE_POSTGRES:-postgres:15}"

# Show what's being used
print_info "Using image: $POSTGRES_IMAGE"
if [[ "$POSTGRES_IMAGE" == *"artifactory"* ]]; then
    print_info "Corporate Artifactory detected"
fi
```

### State Management

**Option A: Stateless (Preferred)**
- Check actual state (is container running? is file present?)
- Don't track "setup ran" separately
- Idempotency comes from reality checks

**Option B: State Files**
- Write `/tmp/.component-setup-complete`
- Useful for complex multi-step flows
- Can be confusing if out of sync with reality

**Recommendation:** Use Option A (stateless) for new scripts unless complexity demands otherwise.

---

## Integration Patterns

### How Setup Scripts Integrate

**1. Called by Wizard** (future)
```bash
# dev-tools/setup-platform.sh (when we create it)
./setup-scripts/setup-kerberos.sh --yes
./setup-scripts/setup-pagila.sh --yes
./setup-scripts/setup-openmetadata.sh --yes
```

**2. Run Standalone**
```bash
# Developer just needs pagila
./setup-scripts/setup-pagila.sh
```

**3. Called by Makefile**
```bash
# Makefile
setup-pagila: ## Setup pagila test database
	@./setup-scripts/setup-pagila.sh
```

**4. Documentation References**
```markdown
See `setup-scripts/setup-pagila.sh` for automated setup,
or follow manual steps below...
```

### Dependency Handling

**How scripts handle prerequisites:**

```bash
# In setup-openmetadata.sh (example)

check_prerequisites() {
    local all_ok=true

    # Check if platform network exists
    if ! docker network inspect platform_network >/dev/null 2>&1; then
        print_error "platform_network not found"
        print_info "Run: docker network create platform_network"
        all_ok=false
    fi

    # Check if Kerberos sidecar is available (optional)
    if ! docker images | grep -q "platform/kerberos-sidecar"; then
        print_warning "Kerberos sidecar not built yet"
        print_info "OpenMetadata will work, but SQL Server ingestion needs Kerberos"
        print_info "Run: ./setup-scripts/setup-kerberos.sh"
    fi

    return $([ "$all_ok" = true ])
}
```

**Scripts are informative but not blocking** - let user decide.

---

## Rework Assessment: Current State Analysis

### What Exists Now

**`dev-tools/setup-kerberos.sh`** - 11-step wizard
- ✅ Works well
- ✅ Users have tested it
- ✅ Recent PRs fixed issues
- ❌ Monolithic (1000+ lines)
- ❌ Named "kerberos" but does more

**Is it worth refactoring NOW?**

**Arguments FOR immediate refactor:**
- Establishes pattern correctly from the start
- Cleaner for future additions
- Easier to test components

**Arguments AGAINST immediate refactor:**
- High risk (lots of tested code to break)
- You haven't tested OpenMetadata yet
- Unclear if complexity is actually painful
- Could refactor when adding 3rd wizard

### My Ultrathought Recommendation

**Hybrid: Establish pattern, don't force rework**

**Phase 1 (This Session):**
1. ✅ Create `setup-scripts/` directory (new home for focused scripts)
2. ✅ Create `setup-scripts/README.md` (establish pattern)
3. ✅ Create `setup-scripts/setup-pagila.sh` (first modular script!)
4. ✅ Update `.env.example` with pagila hooks
5. ❌ **Don't refactor setup-kerberos.sh yet**

**Phase 2 (After You Test Everything):**
1. Collect feedback on current wizard
2. Identify actual pain points
3. Decide: Extract components or create new orchestrator?
4. Refactor based on **real experience**

**Why this is better:**
- Low risk (only touching new code)
- Establishes pattern (pagila shows the way)
- Defers rework until value is proven
- You get to test before major refactoring

## Specific Implementation Plan

### What I'll Create Right Now

**File: `setup-scripts/setup-pagila.sh`**
```bash
#!/bin/bash
# Setup Pagila Test Database
# ==========================
# Idempotent: Yes
# Prerequisites: Docker running, platform_network exists
# Corporate: Respects IMAGE_POSTGRES from .env
```

**File: `setup-scripts/README.md`**
- Documents modular pattern
- Shows how to add new setup scripts
- Explains when to use which approach

**Update: `.env.example`**
```bash
# Pagila Test Database
IMAGE_PAGILA_POSTGRES=${IMAGE_POSTGRES:-postgres:15}
PAGILA_PORT=5432
```

**Update: `Makefile`**
```makefile
setup-pagila: ## Setup pagila test database
	@./setup-scripts/setup-pagila.sh
```

**File: `docs/setup-scripts-architecture.md`** (optional)
- Explains modular vs monolithic
- When to use each
- Migration path

### What I WON'T Do (Yet)

- ❌ Refactor `dev-tools/setup-kerberos.sh` into modules
- ❌ Create `setup-scripts/setup-openmetadata.sh` (not needed yet)
- ❌ Create orchestrator wizard (premature)
- ❌ Move existing scripts (wait for pain points)

---

## Long-Term Vision (For Reference)

**When we have 5+ components:**

```
setup-scripts/
├── README.md
├── setup-kerberos.sh      (extracted from wizard)
├── setup-pagila.sh        (created now)
├── setup-openmetadata.sh  (if complex setup emerges)
├── setup-airflow.sh       (if needed)
└── setup-spark.sh         (future)

dev-tools/
├── setup-platform.sh      (orchestrator - calls all scripts)
└── setup-kerberos.sh      (legacy - deprecated, points to new location)
```

**But we don't need that complexity yet!**

---

## Does This Make Sense?

**Summary of my recommendation:**

1. **Create modular pagila setup NOW** (new code, establishes pattern)
2. **Leave Kerberos wizard alone** (works, refactor later if needed)
3. **No OpenMetadata wizard** (just `make platform-start`)
4. **Document the pattern** (so future work follows it)
5. **Evolve based on feedback** (real pain, not theoretical)

**Key insight:** Start the modular pattern with pagila (low risk) without forcing a risky refactor of working code (Kerberos wizard).

**Does this balance your vision for modularity with pragmatism?** Should I proceed with creating `setup-pagila.sh` and documenting the pattern?# Test comment
