# Claude Development Guidelines

Development patterns, Git workflows, and lessons learned established for the airflow-data-platform repository, incorporating insights from repository separation and platform-as-dependency architecture.

## 🏗️ Repository Architecture Evolution

### Platform Separation (Major Learning)
**Previous**: Monorepo with mixed platform and business code
**Current**: Clean separation into platform and examples repositories

**Key Insight**: Repository separation prevents merge conflicts when businesses fork examples while allowing platform updates via dependency management.

**Architecture**:
- **Platform Repository** (`airflow-data-platform`): Generic `sqlmodel-framework` only
- **Examples Repository** (`airflow-data-platform-examples`): Business implementations using platform as UV dependency
- **Business Workflow**: Fork examples → customize → pull platform updates automatically

## 🔄 Git Workflow Standards

### Conventional Commits Format
All commits follow the **Conventional Commits** specification:

```
<type>: <description>

[optional body]

[optional footer]
```

**Commit Types:**
- `feat:` - New features or enhancements
- `fix:` - Bug fixes and corrections
- `docs:` - Documentation changes
- `style:` - Code formatting and style improvements
- `refactor:` - Code restructuring without changing functionality
- `test:` - Adding or modifying tests
- `chore:` - Maintenance tasks

**Examples:**
```bash
git commit -m "feat: add sqlmodel-framework platform separation"
git commit -m "fix: resolve Field() server_default compatibility issues"
git commit -m "docs: update platform-as-dependency documentation"
```

### Current Branching Strategy
- **Main branch**: `main` (protected, requires PRs)
- **Feature branches**: `feature/layer2-data-processing-v2` (current active)
- **Working Branch**: Currently on `feature/layer2-data-processing-v2`

**Critical Pattern**:
- Platform changes in `airflow-data-platform` repository
- Example fixes in `airflow-data-platform-examples` repository
- Separate but coordinated development workflows

## 📝 Technical Lessons Learned

### 1. SQLModel Field Patterns (Critical Fix)
**Learning**: SQLModel Field() and SQLAlchemy Column() server_default handling is nuanced.

**What Broke**:
```python
# This causes TypeError: Field() got unexpected keyword argument 'server_default'
activebool: bool = Field(nullable=False, default=True, server_default=text("true"))
```

**Correct Pattern**:
```python
# server_default goes in sa_column, default stays in Field()
activebool: bool = Field(
    sa_column=Column(nullable=False, server_default=text("true")),
    default=True
)
```

**Why This Matters**: Enables platform-as-dependency pattern with UV installations.

### 2. UV Dependency Management
**Learning**: Git dependencies require specific configuration patterns.

**Required Configuration**:
```toml
# In pyproject.toml
[tool.hatch.metadata]
allow-direct-references = true

[tool.hatch.build.targets.wheel]
packages = ["datakits"]

dependencies = [
    "sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@feature/layer2-data-processing-v2#subdirectory=data-platform/sqlmodel-workspace/sqlmodel-framework"
]
```

### 3. Test Infrastructure Architecture
**Learning**: PostgreSQL sandbox with automated bootstrap/teardown is essential.

**Working Pattern**:
```bash
./scripts/test-with-postgres-sandbox.sh
# ✅ Bootstraps PostgreSQL container
# ✅ Runs 22/22 framework tests
# ✅ Tests deployment script
# ✅ Clean teardown
```

**Key Insight**: Docker Compose `version:` attribute is obsolete and causes warnings.

### 4. Directory Structure Evolution
**Previous**: `data-workspace/data-platform-framework/`
**Current**: `data-platform/sqlmodel-workspace/sqlmodel-framework/`

**Impact**: All test paths needed updating for new structure.

### 5. Import Structure Consistency
**Learning**: Framework renames must be complete and consistent.

**Pattern Applied**:
- `data_platform_framework` → `sqlmodel_framework`
- Updated all imports, tests, and deployment scripts
- Ensured no lingering old references

## 🧪 Testing Patterns That Work

### 1. Multi-Database Target Support
```bash
# Fast iteration
python scripts/deploy_datakit.py /path/to/datakit --target sqlite_memory

# Full PostgreSQL testing
python scripts/deploy_datakit.py /path/to/datakit --target postgres_local --validate
```

### 2. Framework Core Validation
```bash
# Table mixins (11/11 tests)
PYTHONPATH="./src:$PYTHONPATH" uv run -m pytest tests/unit/test_table_mixins.py -v

# Trigger builder (11/11 tests)
PYTHONPATH="./src:$PYTHONPATH" uv run -m pytest tests/unit/test_trigger_builder.py -v
```

### 3. Platform-as-Dependency Testing
```bash
# From examples repository
cd pagila-implementations/pagila-sqlmodel-basic
uv sync  # Should install framework from Git successfully
```

## 🛠️ Technical Patterns That Work

### 1. Table Mixin Architecture
```python
# Clean mixin inheritance
class ReferenceTableMixin(SQLModel):
    inactivated_date: datetime | None = Field(default=None)
    systime: datetime = Field(default_factory=lambda: datetime.now(UTC))

class TransactionalTableMixin(SQLModel):
    systime: datetime = Field(default_factory=lambda: datetime.now(UTC))
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
```

### 2. Abstract Base Classes
```python
class ReferenceTable(ReferenceTableMixin, SQLModel):
    __abstract__ = True  # Critical: prevents direct instantiation
```

### 3. Deployment Script Pattern
```python
# Generic deployment to any datakit path
deploy_data_objects(table_classes, target_config)
# Supports multiple database targets
# Handles schema creation and validation
```

## 🎯 Documentation Strategies

### 1. Platform vs Examples Separation
**Platform Docs**: Technical framework documentation, API reference
**Examples Docs**: User-facing guides, getting started, business implementations

### 2. Test Plan Integration in PRs
```markdown
## Test Plan
### 1. Framework Core Tests
- [ ] 11/11 table mixin tests pass
- [ ] 11/11 trigger builder tests pass

### 2. Platform Integration
- [ ] UV sync installs framework from Git
- [ ] Deployment script discovers tables correctly
```

### 3. Architecture Decision Documentation
- Repository separation rationale clearly explained
- Migration path for business forks documented
- Platform-as-dependency benefits outlined

## 🚀 Current State & Future Work

### ✅ Completed Successfully
- Repository separation (platform vs examples)
- SQLModel compatibility fixes
- UV dependency installation working
- PostgreSQL test sandbox operational
- All 22 framework tests passing
- Updated PR descriptions and documentation

### 📋 Identified for Future Implementation
**Issue #8**: Missing table mixin column patterns
- Version tracking mixins
- Audit trail patterns (created_by/updated_by)
- Temporal versioning for advanced use cases
- Base column conflict resolution

### 🎉 Ready for Production Use
The framework separation provides:
- Clean business fork workflow
- Automated platform updates via UV dependency management
- Robust test infrastructure with PostgreSQL sandbox
- Production-ready table mixins and triggers
- Comprehensive deployment tooling

## 🔄 Development Process Insights

### 1. Real-World Testing is Essential
- Corporate environment constraints surface different issues
- User feedback reveals assumptions in documentation
- Cross-platform boundaries (Windows/WSL2) multiply complexity

### 2. Repository Architecture Decisions Have Long-Term Impact
- Early platform/examples separation prevents future merge conflicts
- Clean dependency patterns enable automated updates
- Test infrastructure design affects development velocity

### 3. Framework Compatibility is Critical
- SQLModel patterns must be precisely correct
- UV dependency management requires specific configuration
- Import structure changes must be complete and consistent

---

*This document captures lessons learned through February 2025, incorporating repository separation, platform-as-dependency architecture, and production deployment experience.*
