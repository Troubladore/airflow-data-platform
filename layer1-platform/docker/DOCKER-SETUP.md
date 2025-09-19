# Docker Setup for Layer 1 Infrastructure

## WSL2 + Docker Desktop Integration

This Layer 1 infrastructure requires Docker for running database containers and services.

### Setup Steps

1. **Install Docker Desktop** (if not already installed)
2. **Enable WSL2 Integration**:
   - Open Docker Desktop Settings
   - Go to Resources → WSL Integration
   - Enable integration for your WSL2 distribution
   - Apply & Restart

3. **Verify Installation**:
   ```bash
   docker --version
   docker compose version
   ```

### Alternative: Remote Docker Environment

If WSL2 integration isn't available, you can:

1. **Use remote Docker daemon** via `DOCKER_HOST` environment variable
2. **Run on separate machine** and update connection strings in Layer 2 datakits
3. **Use cloud databases** (AWS RDS, Azure PostgreSQL, etc.) for development

### Layer 1 Services

Once Docker is available:

```bash
# Start all Layer 1 infrastructure
./start-pagila-db.sh

# Verify services
docker compose -f pagila-db.yml ps
```

The Pagila database will be accessible at `localhost:15432` for Layer 2 datakit development.
