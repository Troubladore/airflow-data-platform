# 3) Integration & QA (Overview)

Goal: validate cross-service integrations and non-functional requirements before production.

## Key activities
- Deploy same charts/manifests into INT/QA clusters with stricter policies.
- Data validation against golden datasets.
- Performance baselines (e.g., dbt run timings, concurrency behavior).
- Security scans of images and artifacts.

## Verification
- Repeat end-to-end job success using representative volumes.
- dbt tests pass; lineage (if enabled) appears in your chosen tool.
- Resource consumption within agreed budgets.
