# 7. dbt Runner Container

We standardize execution via a `dbt-runner` image.

Build it once:
```bash
cd dbt-runner
docker build -t registry.localhost/analytics/dbt-runner:1.0.0 .
```

Then run any dbt project with:
```bash
docker run --rm -v $PWD/profiles:/app/profiles -v $PWD:/workspace   -w /workspace registry.localhost/analytics/dbt-runner:1.0.0   bash -lc "dbt deps && dbt build --profiles-dir /app/profiles"
```
