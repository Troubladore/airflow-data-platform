# Migration Plan: Aligning to Astronomer-Native Architecture

## 🎯 Changes Required

### 1. Remove/Deprecate Over-Engineered Components

**TO REMOVE:**
- ❌ `kerberos-astronomer/` - Current implementation is too complex for local dev
- ❌ `docker-compose.layer2.yml` - Astronomer handles orchestration
- ❌ `layer1-platform/` - Astronomer IS the platform
- ❌ Complex Makefiles for building base images

**TO KEEP BUT SIMPLIFY:**
- ✅ `platform-bootstrap/` - But make it minimal
- ✅ `scripts/` - But focus on developer setup, not infrastructure

### 2. Restructure Repository

**CURRENT (Too Complex):**
```
airflow-data-platform/
├── kerberos-astronomer/        # ← Remove
├── layer1-platform/            # ← Remove
├── layer2-datakits/            # ← Move to examples repo
├── layer3-warehouses/          # ← Move to examples repo
├── platform-bootstrap/         # ← Simplify
└── data-platform/              # ← Keep
```

**TARGET (Focused):**
```
airflow-data-platform/
├── platform-bootstrap/         # Minimal developer setup
│   ├── registry-cache/        # Offline development
│   ├── ticket-sharer/         # Simple Kerberos sharing
│   └── setup-scripts/         # One-click setup
├── sqlmodel-framework/         # Core framework (from data-platform/)
│   ├── src/                   # Reusable patterns
│   ├── tests/                 # Framework tests
│   └── docs/                  # Framework docs
├── platform-extensions/        # For K8s/production only
│   └── kerberos-sidecar/      # Real sidecar for K8s
└── developer-tools/           # CLI helpers, templates
    ├── templates/             # Astronomer project templates
    └── helpers/               # Wrapper scripts
```

### 3. Specific File Changes

#### A. Simplify platform-bootstrap/

**Current `developer-kerberos-standalone.yml`**: Too complex
**Replace with**: `ticket-sharer.yml` (5 lines, just copies tickets)

**Current `Makefile`**: 300+ lines
**Replace with**: Simple 50-line version focused on:
- `make start` - Start registry + ticket sharer
- `make stop` - Stop services
- `make doctor` - Check prerequisites

#### B. Create Astronomer templates

**NEW**: `developer-tools/templates/`
```
bronze-ingestion/
├── .astro/
│   └── config.yaml      # Pre-configured for Artifactory
├── Dockerfile           # Extends Astronomer image
├── dags/
│   └── example_dag.py   # Uses our patterns
└── requirements.txt     # Include sqlmodel-framework
```

#### C. Move complex components to examples repo

**MOVE** these to `airflow-data-platform-examples`:
- All datakit implementations
- Warehouse definitions
- Complex docker-compose files

### 4. Update Documentation

#### README.md (New Focus)
```markdown
# Airflow Data Platform - Developer Framework

## What This Is
- SQLModel framework for data engineering
- Developer setup tools for Astronomer
- Templates and patterns

## Quick Start (10 minutes)
1. Run setup: `./setup.sh`
2. Start platform: `make start`
3. Create project: `astro dev init --from-template bronze`

## What We DON'T Do
- We don't replace Astronomer
- We don't run Kerberos locally
- We don't manage infrastructure
```

### 5. Implementation Steps

#### Phase 1: Clean Up (1 day)
```bash
# Archive unnecessary components
mkdir deprecated/
mv kerberos-astronomer/ deprecated/
mv layer1-platform/ deprecated/
mv layer2-datakits/ deprecated/
mv layer3-warehouses/ deprecated/

# Document why in deprecated/README.md
```

#### Phase 2: Restructure (1 day)
```bash
# Promote sqlmodel-framework to top level
mv data-platform/sqlmodel-workspace/sqlmodel-framework/ ./

# Simplify platform-bootstrap
cd platform-bootstrap/
rm developer-kerberos-standalone.yml
rm -rf mock-services/
# Keep only: registry-cache.yml, ticket-sharer.yml, setup-scripts/
```

#### Phase 3: Create Templates (2 days)
```bash
# Create Astronomer project templates
mkdir -p developer-tools/templates/
cd developer-tools/templates/

# Bronze template
astro dev init bronze-template
# Customize with our patterns

# Silver template
astro dev init silver-template
# Customize with our patterns
```

#### Phase 4: Update Scripts (1 day)
```bash
# Simplify setup to focus on developer experience
cat > setup.sh << 'EOF'
#!/bin/bash
# One-click developer setup
echo "Setting up Astronomer development environment..."

# 1. Check prerequisites
command -v docker >/dev/null || { echo "Install Docker first"; exit 1; }
command -v astro >/dev/null || { echo "Install Astronomer CLI"; exit 1; }

# 2. Start platform services
cd platform-bootstrap && make start

# 3. Configure Artifactory
./scripts/configure-artifactory.sh

echo "Ready! Run: astro dev init my-project"
EOF
```

### 6. Testing the New Structure

```bash
# Developer should be able to:
cd airflow-data-platform
./setup.sh                    # One-time setup
cd ~/projects
astro dev init my-project --from-template bronze
cd my-project
astro dev start               # Just works

# No Kerberos complexity
# No infrastructure management
# Just develop
```

## 📊 Summary of Changes

| Component | Current State | Target State | Action |
|-----------|--------------|--------------|---------|
| SQLModel Framework | ✅ Good | Keep | None |
| Platform Bootstrap | ⚠️ Too complex | Simplify | Reduce to essentials |
| Kerberos Sidecar | ❌ Wrong place | Move to K8s only | Archive local version |
| Layer Architecture | ❌ Over-engineered | Use Astronomer's | Remove |
| Developer Tools | ⚠️ Missing | Create | Add templates |
| Documentation | ⚠️ Complex | Simplify | Focus on developer |

## 🎯 Success Criteria

After migration, a new developer should:
1. Go from zero to running Airflow in 10 minutes
2. Never see Kerberos complexity
3. Use standard Astronomer commands
4. Have templates that include our patterns
5. Work offline after first setup

## 📅 Timeline

- **Day 1-2**: Clean up and restructure
- **Day 3-4**: Create templates and tools
- **Day 5**: Update documentation
- **Day 6**: Test with fresh developer setup

Total: ~1 week to fully align

## 🚦 Next Steps

1. **Backup current state**: `git branch archive/pre-astronomer-alignment`
2. **Start Phase 1**: Move deprecated components
3. **Test each phase**: Ensure nothing breaks
4. **Document changes**: Update CHANGELOG.md

---

The key insight: **Less is more**. We're removing complexity, not adding it. The repository becomes a thin layer of enterprise glue and patterns on top of Astronomer, not a replacement for it.
