# Astronomer vs Raw Airflow

## Context
We needed Airflow to orchestrate hundreds of DAGs across isolated contracts, each with its own warehouse. Running Airflow “raw” would require deep infra skills in every team.

## Options
- **Raw Airflow**: maximum control, but infra burden on devs, inconsistent environments.
- **Managed SaaS Airflow**: not viable (contracts prohibit externalized services).
- **Astronomer Runtime**: curated images, tested patches, standardized CLI.

## Decision
We chose **Astronomer Runtime** (3.0-10 for Airflow 3.0.6) as the opinionated base.

## Implications
- Faster developer onboarding (Astro CLI spins up local envs).
- Predictable patches (e.g., Airflow 3.0.5 bug was already addressed).
- Easier parity between dev and prod (shared images, same config knobs).
