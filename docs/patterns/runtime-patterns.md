# Runtime Environment Patterns

Solve dependency conflicts and enable team isolation using containerized execution environments.

## 🎯 The Problem We Solve

**Scenario**: Team A needs pandas 1.5, Team B needs pandas 2.0, Team C needs R, and Team D needs PySpark 3.4. All running on the same Airflow instance.

**Without runtime environments**:
- ❌ Dependency conflicts
- ❌ One team blocks others with version requirements
- ❌ Airflow worker gets bloated with everyone's dependencies
- ❌ Environment drift between dev/prod

**With runtime environments**:
- ✅ Each team gets isolated, versioned environments
- ✅ No dependency conflicts
- ✅ Airflow stays clean and focused
- ✅ Teams can use different languages/tools

## 🏗️ Core Concept

Runtime environments are **versioned Docker containers** that contain:
1. **Base runtime** (Python, R, Java, etc.)
2. **Team-specific dependencies** (packages, libraries)
3. **Common enterprise patterns** (logging, auth, utilities)
4. **Execution framework** (how to run transforms)

Teams build their transforms to run in these containers via Astronomer's DockerOperator or KubernetesPodOperator.

## 📦 Base Images We Provide

### 1. Python Transform Environment

For Python-based data transformations:

```dockerfile
# runtime-environments/base-images/python-transform/Dockerfile
FROM python:3.11-slim

# Enterprise patterns
COPY logging_config.py /usr/local/lib/python3.11/site-packages/
COPY auth_utils.py /usr/local/lib/python3.11/site-packages/

# Base data engineering packages
RUN pip install \
    pandas>=2.0,<3.0 \
    sqlalchemy>=2.0,<3.0 \
    pyodbc>=4.0,<5.0 \
    pydantic>=2.0,<3.0

# Execution framework
COPY transform_runner.py /usr/local/bin/
ENTRYPOINT ["python", "/usr/local/bin/transform_runner.py"]
```

**Teams extend this**:

```dockerfile
# Team A's custom environment
FROM runtime-environments/python-transform:v2.1

# Team A specific packages
RUN pip install \
    pandas==1.5.3 \
    scikit-learn==1.3.0 \
    team-a-proprietary-lib==2.1.0

# Team A's transforms
COPY transforms/ /app/transforms/
```

### 2. PySpark Transform Environment

For big data processing:

```dockerfile
# runtime-environments/base-images/pyspark-transform/Dockerfile
FROM apache/spark-py:v3.5.0

# Enterprise patterns
COPY spark_utils.py /opt/spark/python/
COPY enterprise_logging.py /opt/spark/python/

# Additional packages for data engineering
RUN pip install \
    pyspark-extension-lib \
    delta-spark \
    enterprise-spark-utils

COPY spark_runner.py /usr/local/bin/
ENTRYPOINT ["python", "/usr/local/bin/spark_runner.py"]
```

### 3. dbt Transform Environment

For dbt-based transformations:

```dockerfile
# runtime-environments/base-images/dbt-transform/Dockerfile
FROM python:3.11-slim

# Install dbt with enterprise adapters
RUN pip install \
    dbt-core==1.7.0 \
    dbt-sqlserver==1.7.0 \
    dbt-snowflake==1.7.0

# Enterprise dbt macros
COPY macros/ /usr/local/share/dbt/macros/

COPY dbt_runner.py /usr/local/bin/
ENTRYPOINT ["python", "/usr/local/bin/dbt_runner.py"]
```

## 🚀 Usage Patterns with Astronomer

### 1. Local Development (DockerOperator)

```python
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
from datetime import datetime

# Team A's DAG using their custom environment
dag = DAG(
    'team_a_bronze_ingestion',
    start_date=datetime(2024, 1, 1),
    schedule_interval='@daily',
    catchup=False
)

bronze_ingestion = DockerOperator(
    task_id='ingest_sales_data',
    image='registry:5000/runtime-environments/python-transform:team-a-v1.2',
    command='run_transform --config sales_config.yaml',
    environment={
        'SOURCE_DB_CONN': '{{ conn.source_sales_db }}',
        'TARGET_TABLE': 'bronze.raw_sales',
        'EXECUTION_DATE': '{{ ds }}'
    },
    volumes=['shared_data:/app/data'],
    network_mode='bridge',
    dag=dag
)
```

### 2. Production Kubernetes (KubernetesPodOperator)

```python
from airflow.providers.kubernetes.operators.kubernetes_pod import KubernetesPodOperator

# Same transform, different operator for production
bronze_ingestion_prod = KubernetesPodOperator(
    task_id='ingest_sales_data',
    image='company-registry.com/runtime-environments/python-transform:team-a-v1.2',
    cmds=['python', '/usr/local/bin/transform_runner.py'],
    arguments=['run_transform', '--config', 'sales_config.yaml'],
    env_vars={
        'SOURCE_DB_CONN': '{{ conn.source_sales_db }}',
        'TARGET_TABLE': 'bronze.raw_sales',
        'EXECUTION_DATE': '{{ ds }}'
    },
    namespace='airflow-data',
    in_cluster=True,
    dag=dag
)
```

### 3. Environment Abstraction

Create a factory that picks the right operator:

```python
import os
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.providers.kubernetes.operators.kubernetes_pod import KubernetesPodOperator

class RuntimeEnvironment:
    @classmethod
    def create_transform_task(
        cls,
        task_id: str,
        image_name: str,
        transform_config: dict,
        **kwargs
    ):
        """Factory method that creates the right operator for the environment"""

        env = os.getenv('AIRFLOW_ENV', 'local')

        if env == 'local':
            return DockerOperator(
                task_id=task_id,
                image=f'registry:5000/{image_name}',
                environment=transform_config,
                network_mode='bridge',
                **kwargs
            )
        else:
            return KubernetesPodOperator(
                task_id=task_id,
                image=f'company-registry.com/{image_name}',
                env_vars=transform_config,
                namespace='airflow-data',
                in_cluster=True,
                **kwargs
            )

# Usage is environment-agnostic
bronze_task = RuntimeEnvironment.create_transform_task(
    task_id='bronze_ingestion',
    image_name='runtime-environments/python-transform:team-a-v1.2',
    transform_config={
        'SOURCE_DB': '{{ conn.sales_db }}',
        'TARGET_TABLE': 'bronze.sales'
    }
)
```

## 🔧 Team Workflows

### 1. Creating a Team Environment

```bash
# Use our template generator
cd runtime-environments
./templates/create-runtime.sh team-analytics python-transform

# This creates:
# runtime-environments/team-environments/team-analytics/
# ├── Dockerfile                    # Extends base python-transform
# ├── requirements.txt              # Team-specific packages
# ├── transforms/                   # Team's transform library
# ├── tests/                        # Unit tests
# └── Makefile                      # Build/test/deploy
```

**Generated Dockerfile**:
```dockerfile
FROM runtime-environments/python-transform:v2.1

# Team Analytics specific packages
COPY requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt

# Team's transform library
COPY transforms/ /app/transforms/
COPY tests/ /app/tests/

# Set team-specific defaults
ENV TEAM_NAME=analytics
ENV LOG_LEVEL=INFO
ENV DEFAULT_SCHEMA=analytics_bronze
```

### 2. Versioning Strategy

```bash
# Team builds and tags their environment
cd runtime-environments/team-environments/team-analytics
make build tag=v1.3.2

# Produces:
# - registry:5000/runtime-environments/python-transform:team-analytics-v1.3.2
# - registry:5000/runtime-environments/python-transform:team-analytics-latest

# Team updates their DAGs to use new version
image='runtime-environments/python-transform:team-analytics-v1.3.2'
```

### 3. Development to Production Pipeline

```yaml
# .github/workflows/runtime-env.yml (example)
name: Build Team Runtime Environment
on:
  push:
    paths: ['runtime-environments/team-environments/**']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Build and test runtime environment
      run: |
        cd runtime-environments/team-environments/team-analytics
        make build
        make test
        make security-scan

    - name: Push to registries
      run: |
        # Push to local dev registry
        make push registry=registry:5000

        # Push to company registry
        make push registry=company-registry.com
```

## 📊 Advanced Patterns

### 1. Shared Libraries Across Teams

```python
# runtime-environments/shared/enterprise_utils.py
"""Shared utilities available in all runtime environments"""

import logging
import os
from typing import Dict, Any

def setup_enterprise_logging(team_name: str):
    """Standard logging setup for all teams"""
    logging.basicConfig(
        level=os.getenv('LOG_LEVEL', 'INFO'),
        format=f'%(asctime)s - {team_name} - %(levelname)s - %(message)s'
    )

def get_connection_string(conn_name: str) -> str:
    """Standard way to get database connections"""
    # Integrates with Airflow connections or Kubernetes secrets
    return os.getenv(f'CONN_{conn_name.upper()}')

class EnterpriseTransform:
    """Base class for all transforms"""

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.team_name = os.getenv('TEAM_NAME', 'unknown')
        setup_enterprise_logging(self.team_name)
        self.logger = logging.getLogger(__name__)

    def run(self):
        self.logger.info(f"Starting transform: {self.__class__.__name__}")
        try:
            result = self.transform()
            self.logger.info("Transform completed successfully")
            return result
        except Exception as e:
            self.logger.error(f"Transform failed: {e}")
            raise

    def transform(self):
        """Override this in your team's transforms"""
        raise NotImplementedError
```

Teams use the shared patterns:

```python
# Team A's transform
from enterprise_utils import EnterpriseTransform
import pandas as pd

class SalesBronzeIngestion(EnterpriseTransform):
    def transform(self):
        conn_str = self.get_connection_string('sales_db')
        df = pd.read_sql(self.config['query'], conn_str)

        # Team-specific business logic
        df = self.clean_sales_data(df)

        return df
```

### 2. Multi-Language Support

```yaml
# docker-compose.yml for polyglot data team
services:
  python-transform:
    image: runtime-environments/python-transform:team-data-v2.1
    # Python team's transforms

  r-transform:
    image: runtime-environments/r-transform:team-stats-v1.5
    # R team's statistical models

  scala-transform:
    image: runtime-environments/spark-scala:team-ml-v3.2
    # Scala team's Spark jobs

  # All can run on the same Airflow instance!
```

### 3. Resource-Specific Environments

```python
# Different resource profiles for different workloads

# Memory-intensive environment
memory_intensive_task = KubernetesPodOperator(
    task_id='large_aggregation',
    image='runtime-environments/python-transform:memory-optimized-v1.0',
    resources={
        'requests': {'memory': '8Gi', 'cpu': '2'},
        'limits': {'memory': '16Gi', 'cpu': '4'}
    }
)

# CPU-intensive environment
cpu_intensive_task = KubernetesPodOperator(
    task_id='model_training',
    image='runtime-environments/python-transform:cpu-optimized-v1.0',
    resources={
        'requests': {'memory': '4Gi', 'cpu': '8'},
        'limits': {'memory': '8Gi', 'cpu': '16'}
    }
)

# GPU environment for ML
gpu_task = KubernetesPodOperator(
    task_id='deep_learning',
    image='runtime-environments/python-transform:gpu-v1.0',
    resources={
        'limits': {'nvidia.com/gpu': 1}
    }
)
```

## 🧪 Testing Patterns

### 1. Transform Unit Tests

```python
# runtime-environments/team-environments/team-analytics/tests/test_transforms.py
import pytest
from transforms.sales_ingestion import SalesBronzeIngestion
from unittest.mock import Mock

def test_sales_bronze_ingestion():
    """Test the transform logic without external dependencies"""

    # Mock configuration
    config = {
        'query': 'SELECT * FROM sales WHERE date = ?',
        'target_table': 'bronze.sales'
    }

    # Mock the transform
    transform = SalesBronzeIngestion(config)
    transform.get_connection_string = Mock(return_value='mock://connection')

    # Test with mock data
    result = transform.transform()

    assert result is not None
    assert len(result) > 0
```

### 2. Integration Testing

```python
# Test the full container
def test_runtime_environment_integration():
    """Test that the container can execute transforms successfully"""

    import subprocess
    import json

    # Run the container with test config
    result = subprocess.run([
        'docker', 'run', '--rm',
        '-e', 'TEST_MODE=true',
        'runtime-environments/python-transform:team-analytics-v1.2',
        'run_transform', '--config', 'test_config.yaml'
    ], capture_output=True, text=True)

    assert result.returncode == 0
    assert 'Transform completed successfully' in result.stdout
```

## 🎯 Best Practices

### 1. Image Naming and Tagging

```bash
# Consistent naming convention
runtime-environments/{base-type}:{team-name}-v{version}

# Examples:
runtime-environments/python-transform:team-analytics-v1.2.3
runtime-environments/pyspark-transform:team-ml-v2.1.0
runtime-environments/dbt-transform:team-warehouse-v1.0.5
```

### 2. Configuration Management

```python
# Use environment variables for runtime config
# Use mounted files for complex configuration

# In DAG:
transform_task = DockerOperator(
    task_id='transform',
    image='runtime-environments/python-transform:team-a-v1.2',
    environment={
        # Simple config via environment variables
        'SOURCE_TABLE': 'raw_sales',
        'TARGET_SCHEMA': 'bronze',
        'BATCH_DATE': '{{ ds }}'
    },
    volumes=[
        # Complex config via mounted files
        '/path/to/transform_config.yaml:/app/config/transform_config.yaml:ro'
    ]
)
```

### 3. Security Patterns

```dockerfile
# Create non-root user
RUN groupadd -r transform && useradd -r -g transform transform
USER transform

# Only include necessary packages
# Use multi-stage builds to minimize attack surface
FROM python:3.11-slim as builder
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim as runtime
COPY --from=builder /root/.local /root/.local
# Copy only what's needed for runtime
```

### 4. Monitoring and Observability

```python
# Built into base images
import logging
import time
from functools import wraps

def monitor_transform(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start_time = time.time()
        logger = logging.getLogger(__name__)

        logger.info(f"Transform {func.__name__} starting")

        try:
            result = func(*args, **kwargs)
            duration = time.time() - start_time
            logger.info(f"Transform {func.__name__} completed in {duration:.2f}s")
            return result
        except Exception as e:
            duration = time.time() - start_time
            logger.error(f"Transform {func.__name__} failed after {duration:.2f}s: {e}")
            raise

    return wrapper

# Teams use it automatically
@monitor_transform
def my_transform():
    # Business logic here
    pass
```

## 🚀 Migration from Monolith

If you're moving from a monolithic Airflow setup:

### 1. Assessment

```python
# Analyze your current DAGs
# runtime-environments/migration/analyze_dependencies.py

import ast
import os
from collections import defaultdict

def analyze_dag_dependencies(dag_directory):
    """Find all package imports across DAGs"""
    imports = defaultdict(set)

    for root, dirs, files in os.walk(dag_directory):
        for file in files:
            if file.endswith('.py'):
                with open(os.path.join(root, file)) as f:
                    tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            imports[file].add(alias.name)

    return imports

# Results show you which teams need which packages
```

### 2. Gradual Migration

```python
# Phase 1: Hybrid approach
# Some tasks in runtime environments, some in main Airflow

dag = DAG('hybrid_pipeline')

# Old way (running in main Airflow worker)
legacy_task = PythonOperator(
    task_id='legacy_processing',
    python_callable=old_function
)

# New way (running in runtime environment)
new_task = DockerOperator(
    task_id='new_processing',
    image='runtime-environments/python-transform:team-a-v1.0',
    command='run_transform --config new_config.yaml'
)

legacy_task >> new_task  # Mixed execution
```

### 3. Full Migration

```python
# Phase 2: All tasks in runtime environments
dag = DAG('fully_containerized_pipeline')

bronze_task = DockerOperator(
    task_id='bronze_ingestion',
    image='runtime-environments/python-transform:ingestion-v1.2'
)

silver_task = DockerOperator(
    task_id='silver_transformation',
    image='runtime-environments/pyspark-transform:transformation-v2.1'
)

gold_task = DockerOperator(
    task_id='gold_aggregation',
    image='runtime-environments/python-transform:aggregation-v1.0'
)

bronze_task >> silver_task >> gold_task  # Clean isolation
```

## 🎉 Real-World Example

Complete team workflow for a data science team:

```dockerfile
# runtime-environments/team-environments/data-science/Dockerfile
FROM runtime-environments/python-transform:v2.1

# Data science specific packages
RUN pip install \
    scikit-learn==1.3.0 \
    matplotlib==3.7.2 \
    seaborn==0.12.2 \
    jupyter==1.0.0 \
    mlflow==2.6.0

# Team's proprietary ML library
COPY ml_utils/ /usr/local/lib/python3.11/site-packages/ml_utils/

# Model training transforms
COPY transforms/ /app/transforms/
COPY models/ /app/models/

ENV TEAM_NAME=data-science
ENV MLFLOW_TRACKING_URI=https://mlflow.company.com
```

```python
# DAG using the data science environment
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
from datetime import datetime, timedelta

dag = DAG(
    'ml_model_training_pipeline',
    default_args={
        'depends_on_past': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=5),
    },
    start_date=datetime(2024, 1, 1),
    schedule_interval='@weekly',
    catchup=False
)

# Feature engineering
feature_engineering = DockerOperator(
    task_id='feature_engineering',
    image='runtime-environments/python-transform:data-science-v2.3',
    command='run_transform --transform feature_engineering --config /app/config/features.yaml',
    environment={
        'SOURCE_TABLE': 'silver.customer_events',
        'TARGET_TABLE': 'gold.ml_features',
        'FEATURE_DATE': '{{ ds }}'
    },
    dag=dag
)

# Model training
model_training = DockerOperator(
    task_id='model_training',
    image='runtime-environments/python-transform:data-science-v2.3',
    command='run_transform --transform train_model --config /app/config/model.yaml',
    environment={
        'FEATURES_TABLE': 'gold.ml_features',
        'MODEL_NAME': 'customer_churn_v2',
        'MLFLOW_EXPERIMENT': 'customer_churn'
    },
    dag=dag
)

# Model validation
model_validation = DockerOperator(
    task_id='model_validation',
    image='runtime-environments/python-transform:data-science-v2.3',
    command='run_transform --transform validate_model --config /app/config/validation.yaml',
    environment={
        'MODEL_NAME': 'customer_churn_v2',
        'VALIDATION_DATASET': 'gold.ml_validation',
        'ACCURACY_THRESHOLD': '0.85'
    },
    dag=dag
)

feature_engineering >> model_training >> model_validation
```

This pattern gives each team complete control over their dependencies while maintaining enterprise standards and Astronomer integration!

---

**Next**: See [Migration Patterns](migration-patterns.md) for moving existing pipelines to this architecture.
