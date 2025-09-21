# Lessons Learned: Repository Separation & Platform-as-Dependency Architecture

## 🎯 Project Overview
Successfully transformed airflow-data-platform from a monorepo with mixed platform/business code into a clean platform-as-dependency architecture, enabling businesses to fork examples without merge conflicts while automatically receiving platform updates.

## 🏆 Key Achievements
- **Platform-as-Dependency Pattern**: Generic framework installable via UV from Git
- **Repository Separation**: Clean platform vs examples split prevents business fork conflicts
- **SQLModel Compatibility**: Fixed Field/sa_column server_default patterns
- **Test Infrastructure**: PostgreSQL sandbox with automated bootstrap/teardown
- **Framework Validation**: 22/22 tests passing across table mixins and trigger builder

## 🔍 Critical Lessons Learned

### 1. Repository Architecture Decisions Have Exponential Impact
**Learning**: Early separation decisions prevent exponentially complex merge conflicts later.

**What Happened**:
- Monorepo mixing platform and business code created fork complexity
- Businesses needed to customize examples but feared merge conflicts with platform updates
- Single repository made it unclear what was generic vs business-specific

**Solution**:
- **Platform Repository** (`airflow-data-platform`): Only generic `sqlmodel-framework`
- **Examples Repository** (`airflow-data-platform-examples`): Business implementations using platform dependency
- **Business Workflow**: Fork examples → add platform as UV dependency → customize without conflicts

**Long-term Impact**: Businesses can now safely fork examples while receiving platform updates automatically.

### 2. SQLModel Field Patterns Are Critically Precise
**Learning**: SQLModel Field() vs SQLAlchemy Column() server_default handling has nuanced rules.

**What Broke**:
```python
# This causes: TypeError: Field() got unexpected keyword argument 'server_default'
activebool: bool = Field(nullable=False, default=True, server_default=text("true"))
```

**Root Cause**: `server_default` must be in SQLAlchemy Column, not SQLModel Field.

**Correct Pattern**:
```python
# server_default in sa_column, Python default in Field()
activebool: bool = Field(
    sa_column=Column(nullable=False, server_default=text("true")),
    default=True
)
```

**Impact**: This pattern enables UV installation from Git repositories and proper database schema generation.

### 3. UV Dependency Management Requires Specific Configuration
**Learning**: Git-based dependencies need precise hatch configuration.

**What Broke**: Direct UV sync failed with "cannot be a direct reference" errors.

**Required Configuration**:
```toml
[tool.hatch.metadata]
allow-direct-references = true

[tool.hatch.build.targets.wheel]
packages = ["datakits"]

dependencies = [
    "sqlmodel-framework @ git+https://github.com/Troubladore/airflow-data-platform.git@feature/layer2-data-processing-v2#subdirectory=data-platform/sqlmodel-workspace/sqlmodel-framework"
]
```

**Success Pattern**: This enables `uv sync` to install framework directly from Git subdirectory.

### 4. Test Infrastructure Must Handle Database Lifecycle
**Learning**: Framework testing requires automated PostgreSQL bootstrap/teardown.

**What Worked**:
- Docker Compose PostgreSQL container on test-specific port (15444)
- Automated database creation and schema setup
- Clean teardown preventing test pollution
- Support for multiple database targets (SQLite, PostgreSQL, MySQL)

**Critical Fix**: Removed obsolete `version:` from docker-compose.yml to eliminate warnings.

**Test Results**:
```bash
✅ Framework core tests: 11/11 passing
✅ Trigger builder tests: 11/11 passing
✅ Example deployment: 6 tables discovered
✅ PostgreSQL integration: Working
```

### 5. Directory Structure Changes Cascade Through Entire Codebase
**Learning**: Framework renames require comprehensive consistency checks.

**What Changed**:
- `data-workspace/data-platform-framework/` → `data-platform/sqlmodel-workspace/sqlmodel-framework/`
- `data_platform_framework` → `sqlmodel_framework` (all imports)
- Test paths, deployment scripts, documentation all updated

**Pattern Applied**: Search for ALL references before considering rename complete.

**Validation Required**: Ensure no lingering old references in any file type.

## 🛠️ Technical Patterns That Proved Essential

### 1. Abstract Base Class Pattern
```python
class ReferenceTable(ReferenceTableMixin, SQLModel):
    __abstract__ = True  # Critical: prevents direct instantiation

# Usage in business code:
class Category(ReferenceTable, table=True):
    __tablename__ = "category"
    category_id: int = Field(primary_key=True)
    name: str = Field(nullable=False)
```

**Why This Works**: Business tables inherit mixin behavior without framework base class conflicts.

### 2. Multi-Database Deployment Architecture
```python
# Fast development iteration
deploy_datakit.py /path/to/datakit --target sqlite_memory

# Full integration testing
deploy_datakit.py /path/to/datakit --target postgres_local --validate

# Container-based testing
deploy_datakit.py /path/to/datakit --target postgres_container --validate
```

**Key Insight**: Multiple target types enable different testing workflows.

### 3. Framework Discovery Pattern
```python
def discover_sqlmodel_classes(modules: list[ModuleType]) -> list[type[SQLModel]]:
    # Automatically finds table classes in any datakit
    # Handles abstract base classes correctly
    # Supports schema-aware deployments
```

**Impact**: Generic deployment script works with any business datakit structure.

## 🎯 Documentation Architecture Insights

### 1. Platform vs Examples Documentation Split
**Platform Docs** (Technical):
- Framework internals and API reference
- SQLModel patterns and mixin usage
- Deployment script architecture
- Test infrastructure setup

**Examples Docs** (Business):
- Getting started guides
- Implementation examples
- Business workflow patterns
- Platform dependency installation

### 2. PR Description Evolution
**Before**: Mixed technical and business scope
**After**: Clear platform-only focus with migration path documentation

**Pattern**: Each repository's PRs focus on their specific scope and cross-reference related work.

### 3. Issue Management Strategy
**Platform Issues**: Framework enhancements, technical debt, architecture
**Examples Issues**: Business implementation testing, documentation, user experience

**Cross-Linking**: Issues reference related work in the other repository.

## 🧪 Testing Strategies That Scale

### 1. Tiered Testing Approach
```bash
# Unit: Framework core (22 tests)
pytest tests/unit/

# Integration: PostgreSQL sandbox
./scripts/test-with-postgres-sandbox.sh

# End-to-end: Examples repository deployment
uv sync && python deploy_script.py
```

### 2. Platform-as-Dependency Validation
```bash
# In examples repository
cd pagila-implementations/pagila-sqlmodel-basic
uv sync  # Must succeed without errors
```

**Success Criteria**: Framework installs cleanly from Git with all dependencies resolved.

### 3. Cross-Repository Integration Testing
- Platform changes trigger examples repository validation
- Examples issues can identify platform framework gaps
- Coordinated release workflow ensures compatibility

## 🚀 Success Patterns for Future Framework Work

### Apply These Lessons:
1. **Separate platform from business early** - prevents merge conflict complexity
2. **Precise SQLModel patterns** - Field() vs sa_column() server_default handling
3. **UV dependency configuration** - allow-direct-references and wheel packages
4. **Automated test infrastructure** - PostgreSQL sandbox for integration testing
5. **Comprehensive rename validation** - search entire codebase for consistency
6. **Documentation separation** - technical vs user-facing guides

### Avoid These Anti-Patterns:
1. **Mixing platform and business code** - creates fork complexity
2. **Assuming SQLModel patterns** - test Field() configurations thoroughly
3. **Manual dependency management** - use UV with proper hatch configuration
4. **Manual database setup** - automate PostgreSQL lifecycle for testing
5. **Incomplete renames** - old references break in unexpected places
6. **Monolithic documentation** - separate technical and user concerns

## 📊 Metrics of Success

### Repository Separation
- ✅ **Platform Repository**: Contains only generic framework code
- ✅ **Examples Repository**: Contains only business implementations
- ✅ **UV Integration**: Framework installs cleanly as Git dependency
- ✅ **Business Workflow**: Clear fork → customize → update pattern

### Technical Framework
- ✅ **Test Coverage**: 22/22 tests passing
- ✅ **Database Support**: PostgreSQL, MySQL, SQLite targets working
- ✅ **SQLModel Compatibility**: Field/sa_column patterns correct
- ✅ **Deployment Script**: Generic datakit deployment working

### User Experience
- ✅ **Documentation Split**: Technical vs business guides separated
- ✅ **Testing Workflow**: Automated PostgreSQL sandbox operational
- ✅ **Issue Management**: Platform and examples issues properly separated
- ✅ **PR Strategy**: Clear scope and cross-repository coordination

## 🎉 Ready for Production Business Forks

With repository separation complete and platform-as-dependency working:

### For Businesses:
1. **Fork examples repository** (not platform)
2. **Add platform dependency** via UV configuration
3. **Customize examples** without merge conflict concerns
4. **Receive platform updates** automatically via dependency management

### For Platform Development:
1. **Focus on generic framework** improvements
2. **Validate with examples repository** testing
3. **Coordinate releases** with examples compatibility
4. **Track framework usage** across business implementations

The foundation provides the architecture needed for scalable business customization while maintaining platform consistency and enabling automated updates.

---

*Lessons learned through repository separation completion, February 2025.*
