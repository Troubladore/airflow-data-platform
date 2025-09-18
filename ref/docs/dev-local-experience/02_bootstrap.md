# 2. Bootstrapping the Environment

1. Clone repos (platform, datakits, dbt packages, traefik-bundle, local registry).
2. Start Traefik + Registry:
   ```bash
   cd astro-local-config/traefik-bundle
   docker compose up -d
   ```
   - Exposes registry at `registry.localhost`.
   - Handles TLS with certs from IT process.

3. Validate registry:
   ```bash
   docker pull busybox
   docker tag busybox registry.localhost/test/busybox:latest
   docker push registry.localhost/test/busybox:latest
   ```

4. Confirm `.localhost` routing with Traefik:
   - Visit `https://airflow-dev.customer.localhost`
   - Traefik terminates TLS with IT-provided certs.
