# dbt Core + Postgres adapter
FROM python:3.11.9-slim

ENV PIP_NO_CACHE_DIR=1     DBT_TARGET=dev

# System deps for Postgres + git (packages)
RUN apt-get update && apt-get install -y --no-install-recommends     git build-essential libpq-dev  && rm -rf /var/lib/apt/lists/*

# Fast installer
RUN pip install uv

# dbt-core & dbt-postgres (pin as desired)
RUN uv pip install --system "dbt-core>=1.7,<1.9" "dbt-postgres>=1.7,<1.9"

# Optional: OpenLineage for dbt (uncomment to emit lineage)
# RUN uv pip install --system "openlineage-integration-common>=1,<2" "openlineage-dbt>=1,<2"

WORKDIR /app
# Profiles are expected at /app/profiles (mount at runtime)
CMD ["/bin/bash","-lc","dbt --help"]
