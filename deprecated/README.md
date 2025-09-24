# Deprecated Components - Migration Rationale

## 🎯 Migration Philosophy

We're aligning with Astronomer's architecture rather than reinventing wheels. However, we're preserving valuable **patterns** that work ON TOP of Astronomer.

## Component Decisions

### ✅ DEPRECATE: layer1-platform/
**Why Deprecate**: Astronomer IS the platform layer
- Astronomer provides local development via Astro CLI
- Astronomer provides production deployment patterns
- Astronomer provides service orchestration (webserver, scheduler, workers)
- Our registry caching optimizations can be done via standard Astronomer config

**What We Gain**:
- Standard Astronomer tooling and commands
- Community support and documentation
- Automatic updates and security patches

**What We Don't Lose**:
- Registry caching (implement via Astronomer's registry config)
- Fixed image versions (use Astronomer's versioning)
- Optimization patterns (apply through standard Astronomer mechanisms)

### 🔄 MOVE TO EXAMPLES: layer2-datakits/
**Why NOT Deprecate**: The datakit pattern is VALUABLE and complements Astronomer
- **Pattern**: Containerized, versioned transformation environments
- **Value**: Dependency isolation from Airflow runtime
- **How Astronomer Helps**: Provides operators (DockerOperator, KubernetesPodOperator)

**Migration Path**:
```python
# Old: Custom datakit runner
DatakitRunner.execute(datakit="bronze-ingestion")

# New: Astronomer operators with datakit pattern
KubernetesPodOperator(
    task_id="bronze_ingestion",
    image="my-registry/datakits/bronze-ingestion:v1.2.3",
    # Datakit pattern preserved, Astronomer operators used
)
```

**Decision**: Move to `airflow-data-platform-examples/datakits/`
- Show how datakit pattern works WITH Astronomer operators
- Preserve versioning and isolation benefits
- Use standard operators instead of custom runners

### 🔄 MOVE TO EXAMPLES: layer2-dbt-projects/
**Why NOT Deprecate**: Alternative to SQLModel worth showcasing
- Shows dbt integration pattern with Astronomer
- Different approach that some teams prefer
- Complements rather than competes with SQLModel

**Decision**: Move to `airflow-data-platform-examples/dbt-patterns/`

### 🔄 MOVE TO EXAMPLES: layer3-warehouses/
**Why NOT Deprecate**: "Warehouse as config" is a GREAT pattern
- Not provided by Astronomer (sits on top)
- Enables "define once, deploy many" for warehouses
- Critical for multi-environment deployments

**Decision**: Move to `airflow-data-platform-examples/warehouse-patterns/`
- Show how this pattern enhances Astronomer deployments
- Preserve the config-driven warehouse definitions
- Document integration with Astronomer connections

### ✅ DEPRECATE: kerberos-astronomer/ (complex version)
**Why Deprecate**: Over-engineered for local development
- Running full KDC locally is too complex
- Developers already have WSL2 Kerberos tickets
- Simple ticket sharing is sufficient

**Replacement**: Minimal ticket-sharer in platform-bootstrap/
- Just copies existing WSL2 tickets to containers
- No complex Kerberos infrastructure
- Works with developer's existing corporate authentication

## 📊 Summary Table

| Component | Action | Destination | Rationale |
|-----------|--------|------------|-----------|
| layer1-platform | DEPRECATE | - | Astronomer provides this |
| layer2-datakits | MOVE | examples/datakits/ | Valuable pattern, use with Astronomer operators |
| layer2-dbt-projects | MOVE | examples/dbt-patterns/ | Alternative approach worth preserving |
| layer3-warehouses | MOVE | examples/warehouse-patterns/ | Great pattern that enhances Astronomer |
| kerberos-astronomer | DEPRECATE | - | Replace with simple ticket sharing |

## 🚀 Key Insight

The migration isn't about throwing away all our work. It's about:
1. **Removing redundancy** where Astronomer provides solutions
2. **Preserving patterns** that add value on top of Astronomer
3. **Simplifying complexity** for developer experience

## 📝 Migration Notes

### For Datakit Pattern Users
Your datakits remain valuable! We're just changing how they're invoked:
- Continue building versioned transformation containers
- Use Astronomer's operators instead of custom runners
- Benefit from Astronomer's scheduling and monitoring

### For Warehouse Pattern Users
Your config-driven warehouse approach stays:
- Continue defining warehouses as configuration
- Integrate with Astronomer's connection management
- Use environment variables for deployment flexibility

### For DBT Users
Your dbt projects work great with Astronomer:
- Use astronomer-providers-dbt package
- Leverage Astronomer's dbt operators
- Keep your existing project structure

---

*Components archived here are not "bad" - they're redundant with Astronomer's capabilities or need to be repositioned as patterns that enhance rather than replace Astronomer's architecture.*
