# Runtime Environment Patterns

**Read time: 3 minutes**

How to isolate team dependencies using containerized environments with Astronomer.

## 🎯 The Problem

Your data platform has multiple teams:
- Team A needs pandas 1.5
- Team B needs pandas 2.0
- Team C needs R
- Team D needs PySpark 3.4

Without runtime environments, you get dependency conflicts. With them, each team works in isolation.

## 🏗️ Core Concepts

### Runtime Environment
A **versioned Docker container** that runs your team's data transformations. Think of it as a "workspace in a box" that contains everything your team needs.

### Base Image
A **starting template** we provide with common tools pre-installed. Teams extend these templates with their specific needs.

### The Flow
1. We provide **base images** (templates)
2. Teams extend them to create **runtime environments** (their workspace)
3. Astronomer runs these environments using **DockerOperator** or **KubernetesPodOperator**

## 📦 Available Base Images

We provide **3 base images** as starting templates for teams:

1. **`python-transform`** - For Python data transformations (pandas, SQLAlchemy, etc.)
2. **`pyspark-transform`** - For big data processing with Apache Spark
3. **`dbt-transform`** - For dbt-based SQL transformations

Each base image includes:
- The runtime (Python/Spark/dbt)
- Common enterprise packages
- Logging and monitoring
- Authentication helpers

## 🚀 How It Works with Astronomer

### Step 1: Team Creates Their Environment

Teams start with a base image and add their packages:

```dockerfile
# Team Analytics extends the Python base image
FROM runtime-environments/python-transform:v2.1

# Add team-specific packages
RUN uv pip install --system \
    pandas==1.5.3 \
    scikit-learn==1.3.0 \
    internal-analytics-lib==2.1.0

# Add team's code
COPY transforms/ /app/transforms/
```

### Step 2: Use in Astronomer DAG

Teams use their environment in Airflow DAGs:

```python
from airflow.providers.docker.operators.docker import DockerOperator

# Run transform in team's isolated environment
transform = DockerOperator(
    task_id='analytics_transform',
    image='runtime-environments/team-analytics:v1.2',
    command='python /app/transforms/daily_metrics.py',
    environment={'DATE': '{{ ds }}'}
)
```

### Step 3: No Conflicts!

- Team Analytics uses pandas 1.5
- Team ML uses pandas 2.0
- Both run on the same Airflow instance
- No conflicts, no problems

## 📖 Learn More

### Quick Starts
- [Creating Your First Runtime Environment](runtime-creating.md) - 5 min tutorial
- [Base Image Reference](runtime-base-images.md) - Details on each base image

### Deep Dives
- [Team Workflow Patterns](runtime-team-workflows.md) - How teams manage environments
- [Local vs Production](runtime-deployment.md) - DockerOperator vs KubernetesPodOperator
- [Security Best Practices](runtime-security.md) - Hardening runtime environments

### Examples
See working examples in the [examples repository](https://github.com/Troubladore/airflow-data-platform-examples):
- [hello-runtime/](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/hello-runtime) - Simplest runtime example
- [team-analytics-runtime/](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/team-analytics-runtime) - Real team setup

## 🎯 Key Takeaway

Runtime environments = **isolated workspaces** for each team.

No more dependency conflicts. No more "works on my machine". Just clean, versioned, isolated execution.

---

**Next**: [Create Your First Runtime Environment](runtime-creating.md) (5 minutes)
