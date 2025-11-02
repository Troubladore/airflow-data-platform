# Platform Setup Wizard

Interactive wizard for configuring and deploying the Airflow Data Platform.

## Automatic Health Checks

The wizard automatically verifies service health after installation:

### PostgreSQL Health Check

After installing PostgreSQL, the wizard runs connectivity tests using the
postgres-test container:

```
✓ PostgreSQL started successfully

Verifying PostgreSQL health...
✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5
```

### Pagila Health Check

After installing Pagila, the wizard verifies sample data is accessible:

```
✓ Pagila installed successfully

Verifying Pagila health...
✓ Pagila healthy - 200 actors, 1,000 films, 16,044 rentals
```

### Health Check Failures

If health checks fail, diagnostics are saved automatically:

```
✓ Pagila installed successfully

Verifying Pagila health...
⚠️  Health check failed: Cannot connect to pagila-postgres
💾 Diagnostics saved to: diagnostic_20251101_143022.log
   Continuing setup...
```

**Note:** Health check failures are non-blocking. The wizard will continue
with setup but save detailed diagnostics for troubleshooting.

### Manual Health Checks

You can run health checks manually at any time:

```bash
# From repository root
make -C platform-infrastructure test-connectivity
```
