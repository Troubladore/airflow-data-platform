# 8. Developer Workflow

Daily flow:
1. **Start platform services** (Traefik + Registry).
2. **Land Bronze data** with datakits.
3. **Run dbt build** in silver-core → gold-core-dimensions → gold topic projects.
4. **Inspect results** in Postgres or dbt docs.
5. **Develop transforms** incrementally in silver/gold repos, validate with `dbt run --select model`.

Key principle: **fidelity** — local builds mimic production shapes (`.localhost` domains, same dbt projects).

No CI/CD yet — just local iteration with Docker + dbt.
