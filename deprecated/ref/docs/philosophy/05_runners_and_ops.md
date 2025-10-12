# Operators and Runner Images

## Context
Some dependencies (SQLModel, PySpark) are incompatible with Airflow’s own deps. We needed isolation without overwhelming devs.

## Options
- **Direct install**: leads to dependency hell.
- **@task.virtualenv**: lightweight, but limited reproducibility.
- **KubernetesPodOperator**: great in prod, but requires local K8s (too heavy).
- **DockerOperator**: container isolation without local K8s.

## Decision
- **DockerOperator locally** with runner images (sqlserver, postgres, spark, dbt).
- **KPO in prod** with the same images.

## Implications
- Devs run locally with Docker Desktop (already installed).
- Prod fidelity: same containers, just different operator backend.
