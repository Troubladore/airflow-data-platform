# Components to Migrate to Examples Repository

These components contain valuable patterns that should be preserved in the `airflow-data-platform-examples` repository rather than deprecated.

## 📦 Components to Move

### 1. layer2-datakits/ → examples/datakits/
**Value**: Containerized, versioned transformation pattern
**Integration**: Use with Astronomer's DockerOperator/KubernetesPodOperator

```bash
# Migration command (run from airflow-data-platform-examples repo)
cp -r ../airflow-data-platform/layer2-datakits ./datakits/
```

**Required Updates**:
- Update DAG examples to use Astronomer operators
- Document the datakit pattern clearly
- Show both local (DockerOperator) and prod (KubernetesPodOperator) usage

### 2. layer2-dbt-projects/ → examples/dbt-patterns/
**Value**: Alternative to SQLModel using dbt
**Integration**: Use astronomer-providers-dbt package

```bash
# Migration command
cp -r ../airflow-data-platform/layer2-dbt-projects ./dbt-patterns/
```

**Required Updates**:
- Add examples using Astronomer's dbt operators
- Document when to choose dbt vs SQLModel
- Include dbt Cloud integration examples if applicable

### 3. layer3-warehouses/ → examples/warehouse-patterns/
**Value**: "Warehouse as config" pattern for multi-environment deployments
**Integration**: Works with Astronomer's connection management

```bash
# Migration command
cp -r ../airflow-data-platform/layer3-warehouses ./warehouse-patterns/
```

**Required Updates**:
- Integrate with Astronomer's connection templates
- Show environment-specific configurations
- Document the pattern's benefits

## 📝 Example Integration Patterns

### Datakit with Astronomer Operators
```python
from astronomer.providers.core.operators.docker import DockerOperator
from astronomer.providers.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
import os

def create_datakit_task(datakit_name: str, config: dict):
    """Factory function for datakit tasks"""

    if os.getenv('ENVIRONMENT') == 'local':
        return DockerOperator(
            task_id=f"run_{datakit_name}",
            image=f"datakits/{datakit_name}:latest",
            environment=config,
            docker_url='unix://var/run/docker.sock',
            network_mode='bridge'
        )
    else:
        return KubernetesPodOperator(
            task_id=f"run_{datakit_name}",
            image=f"registry.company.com/datakits/{datakit_name}:latest",
            env_vars=config,
            namespace='airflow',
            in_cluster=True
        )
```

### Warehouse Pattern with Astronomer
```python
from airflow.models import Connection
from warehouse_patterns import WarehouseConfig

def setup_warehouse_connections(warehouse_config: WarehouseConfig):
    """Create Astronomer connections from warehouse config"""

    for env in ['dev', 'qa', 'prod']:
        conn = Connection(
            conn_id=f"{warehouse_config.name}_{env}",
            conn_type='mssql',
            host=warehouse_config.get_host(env),
            schema=warehouse_config.database,
            port=warehouse_config.port,
            extra={
                'authentication': 'Kerberos',
                'trusted_connection': 'yes'
            }
        )
```

## 🚀 Migration Steps

1. **Create directory structure in examples repo**:
```bash
cd airflow-data-platform-examples
mkdir -p datakits dbt-patterns warehouse-patterns
```

2. **Copy components**:
```bash
# From airflow-data-platform directory
cp -r layer2-datakits/* ../airflow-data-platform-examples/datakits/
cp -r layer2-dbt-projects/* ../airflow-data-platform-examples/dbt-patterns/
cp -r layer3-warehouses/* ../airflow-data-platform-examples/warehouse-patterns/
```

3. **Update imports and references**:
- Change custom operators to Astronomer operators
- Update Docker image references to use proper registry
- Adjust paths for new structure

4. **Add Astronomer-specific documentation**:
- How patterns integrate with Astronomer
- Best practices for each pattern
- Migration guide from custom to Astronomer operators

## ⚠️ Important Notes

### Don't Delete Yet!
These components should remain in airflow-data-platform until:
1. Successfully migrated to examples repository
2. All references updated
3. Documentation complete
4. Tests passing

### Coordination Required
Since these span two repositories:
1. Create feature branch in examples repo first
2. Migrate and test components
3. Update this repo to remove migrated components
4. Coordinate PRs across both repos

## 📋 Checklist for Each Component

- [ ] Copy to examples repository
- [ ] Update to use Astronomer operators
- [ ] Add pattern documentation
- [ ] Create working examples
- [ ] Test in Astronomer environment
- [ ] Update any cross-references
- [ ] Remove from platform repository

---

*This migration preserves the valuable patterns we've developed while aligning with Astronomer's architecture.*
