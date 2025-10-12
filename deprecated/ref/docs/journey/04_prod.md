# 4) Production (Overview)

Goal: deliver isolated, reliable, and auditable pipelines per contract.

## Enclave model
- **Standard** and **High** clusters with separate ingress and guardrails.
- Contracts are pinned to an enclave; same dbt/datakits, different targets and secrets.

## Steps (high level)
1. Hardened images and locked tags.
2. Namespace-per-contract; network policies enforced.
3. Ingress: `airflow-<env>.<customer>.myco.com` (and `airflow-<env>.high.<customer>.myco.com` when needed).
4. Observability: logs/metrics/alerts; lineage where appropriate.
5. Change management: promote only images/models that passed QA.

## Verification
- Blue/green or canary deploys of runner images succeed.
- SLO dashboards show healthy success rates and latency.
- Access reviews confirm contract isolation.
