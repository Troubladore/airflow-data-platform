# Runtime Environments

Isolated execution containers that solve dependency conflicts between teams while maintaining enterprise standards.

## 🎯 Why Runtime Environments?

In enterprise data engineering, different teams need different tools:
- **Analytics team**: pandas 1.5, specific statistical libraries
- **ML team**: pandas 2.0, PyTorch, GPU support
- **Data Engineering**: PySpark, Delta Lake
- **Business Intelligence**: dbt, specific SQL drivers

Without runtime environments, these teams would conflict. With them, everyone can work on the same Astronomer instance without issues.

## 🚀 Quick Example

```python
from airflow.providers.docker.operators.docker import DockerOperator

# Each team gets their exact dependencies, isolated from Airflow
analytics_task = DockerOperator(
    task_id='analytics_transform',
    image='runtime-environments/python-transform:analytics-v1.2',
    # Analytics team's pandas 1.5 environment
)

ml_task = DockerOperator(
    task_id='ml_preprocessing',
    image='runtime-environments/python-transform:ml-v2.1',
    # ML team's pandas 2.0 + PyTorch environment
)
```

## 📦 What We Provide

Base images with enterprise patterns baked in:
- **python-transform** - Standard Python data transformations
- **pyspark-transform** - Big data processing with Spark
- **dbt-transform** - dbt-based SQL transformations
- **r-transform** - Statistical computing with R

Teams extend these bases with their specific needs.

## 📚 Learn More

- **[Runtime Environment Patterns](../docs/patterns/runtime-patterns.md)** - Complete guide
- **[Creating Your Environment](templates/README.md)** - Step-by-step instructions
- **[Base Images](base-images/README.md)** - Available starting points

## 🎯 Key Benefit

**Airflow stays clean and focused on orchestration while teams get exactly the dependencies they need.**
