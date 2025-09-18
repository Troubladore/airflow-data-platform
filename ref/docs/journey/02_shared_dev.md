# 2) Shared Development Cluster (Overview)

Goal: move from laptop-only to a shared K8s environment using the **same images** and the **same dbt projects**.

## What you’ll accomplish
- Push runner images (datakits/dbt) to a shared registry.
- Stand up Astronomer (or vanilla Airflow) on a dev K8s cluster.
- Use KPO for tasks that were DockerOperator locally.

## Steps (high level)
1. **Registry**: mirror `registry.localhost/*` images to your shared registry (e.g., `registry.dev.myco.com`). Tag consistently.
2. **Astronomer Runtime**: install on the dev cluster. Prepare **pod templates** for queues (e.g., `mssql-kerb`, `postgres`, `compute-heavy`).
3. **Secrets**: configure Azure Key Vault (or ESO) bindings for connection strings and credentials.
4. **Routing**: ingress rules for `airflow-dev.<customer>.myco.com`.
5. **Run the same DAGs** you used locally; only the operator backend changes (DockerOperator → KPO).

## Verification
- Airflow web UI reachable at the expected subdomain.
- Task logs show pods starting with the correct images and queues.
- dbt build succeeds, producing the same schemas/tables as local.
