# Creating Your First Runtime Environment

**Read time: 3 minutes**

Step-by-step guide to create a runtime environment for your team.

## Prerequisites

- Docker installed locally
- Access to the platform registry (`registry:5000`)
- Your team's Python packages list

## Step 1: Choose a Base Image

Pick the base that matches your needs:
- **Python transforms?** → `python-transform`
- **Big data/Spark?** → `pyspark-transform`
- **SQL/dbt?** → `dbt-transform`

## Step 2: Create Your Dockerfile

Create a new directory for your team:
```bash
mkdir -p runtime-environments/team-analytics
cd runtime-environments/team-analytics
```

Create `Dockerfile`:
```dockerfile
# Start from Python base image
FROM registry:5000/runtime-environments/python-transform:v2.1

# Add your team's packages
RUN uv pip install --system \
    pandas==1.5.3 \
    matplotlib==3.7.2 \
    scikit-learn==1.3.0

# Copy your transform code
COPY transforms/ /app/transforms/

# Set team name (for logging)
ENV TEAM_NAME=analytics
```

## Step 3: Add Your Transform Code

Create `transforms/daily_metrics.py`:
```python
import pandas as pd
import os

def main():
    # Your transformation logic
    date = os.environ.get('EXECUTION_DATE')
    print(f"Processing metrics for {date}")

    # Read, transform, write...
    df = pd.read_csv('/data/input.csv')
    result = df.groupby('category').sum()
    result.to_csv('/data/output.csv')

if __name__ == "__main__":
    main()
```

## Step 4: Build Your Environment

```bash
# Build the image
docker build -t runtime-environments/team-analytics:v1.0 .

# Test it locally
docker run --rm \
  -e EXECUTION_DATE=2024-01-15 \
  runtime-environments/team-analytics:v1.0 \
  python /app/transforms/daily_metrics.py
```

## Step 5: Use in Your DAG

In your Airflow DAG:
```python
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
from datetime import datetime

dag = DAG(
    'analytics_daily',
    start_date=datetime(2024, 1, 1),
    schedule='@daily'
)

process_metrics = DockerOperator(
    task_id='process_daily_metrics',
    image='runtime-environments/team-analytics:v1.0',
    command='python /app/transforms/daily_metrics.py',
    environment={
        'EXECUTION_DATE': '{{ ds }}'
    },
    dag=dag
)
```

## Step 6: Push to Registry

```bash
# Tag for registry
docker tag runtime-environments/team-analytics:v1.0 \
           registry:5000/runtime-environments/team-analytics:v1.0

# Push to registry
docker push registry:5000/runtime-environments/team-analytics:v1.0
```

## ✅ You're Done!

Your team now has an isolated runtime environment with:
- Your specific package versions
- Your transform code
- No conflicts with other teams

## Common Patterns

### Using pyproject.toml

Instead of `RUN uv pip install`, use a `pyproject.toml`:

```toml
[project]
name = "team-analytics"
version = "1.0.0"
dependencies = [
    "pandas==1.5.3",
    "matplotlib==3.7.2",
    "scikit-learn==1.3.0",
]
```

Then in Dockerfile:
```dockerfile
COPY pyproject.toml /tmp/
RUN cd /tmp && uv sync --system
```

### Multi-stage builds

For smaller images:
```dockerfile
# Build stage
FROM registry:5000/runtime-environments/python-transform:v2.1 as builder
COPY pyproject.toml /tmp/
RUN cd /tmp && uv sync --system

# Runtime stage
FROM python:3.11-slim
COPY --from=builder /usr/local/lib/python3.11 /usr/local/lib/python3.11
COPY transforms/ /app/transforms/
```

## Troubleshooting

**Container won't start?**
- Check logs: `docker logs <container-id>`
- Verify base image exists: `docker pull registry:5000/runtime-environments/python-transform:v2.1`

**Package conflicts?**
- Use `uv pip compile` to resolve dependencies
- Pin all package versions explicitly

**Can't push to registry?**
- Check registry is running: `curl http://registry:5000/v2/`
- Ensure you're on the platform network

---

**Next**: See [example runtime environments](https://github.com/Troubladore/airflow-data-platform-examples/tree/main/runtime-environments-examples)
