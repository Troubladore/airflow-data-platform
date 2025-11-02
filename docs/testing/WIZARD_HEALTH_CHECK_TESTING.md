# Wizard Health Check - Manual Testing Procedure

## Task 5: Base Platform PostgreSQL Health Check Integration

### Purpose
Verify that the PostgreSQL health check runs automatically after successful installation and displays detailed metrics.

### Prerequisites
- Clean environment (no existing platform-postgres container)
- Docker daemon running
- Python environment with wizard dependencies installed

### Test Procedure

#### 1. Start Fresh
```bash
# Clean up any existing containers
cd /home/emaynard/repos/airflow-data-platform/.worktrees/database-health-checks
make -C platform-infrastructure stop
```

#### 2. Run the Wizard
```bash
python -m wizard
```

#### 3. Install PostgreSQL
- Select option to install/configure PostgreSQL
- Choose default settings (postgres:17.5-alpine, trust auth)
- Proceed with installation

#### 4. Verify Health Check Output

**Expected output after installation:**
```
Starting PostgreSQL service...
  Image: postgres:17.5-alpine
  Auth: trust (no password)
✓ PostgreSQL started successfully

Verifying PostgreSQL health...
✓ Platform postgres healthy - 2 databases, PostgreSQL 17.5
```

**Key validation points:**
- [x] "Verifying PostgreSQL health..." message appears
- [x] Health check runs automatically (no user intervention)
- [x] Success message shows database count (2 databases)
- [x] Success message shows PostgreSQL version (17.5)
- [x] No errors or warnings appear

#### 5. Verify Container Status
```bash
docker ps --filter name=platform-postgres --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected:
- platform-postgres container is running
- postgres-test container is running

#### 6. Test Health Check Failure (Optional)

To test failure handling:
```bash
# Stop postgres-test container to simulate health check failure
docker stop postgres-test

# Restart PostgreSQL via wizard
python -m wizard
# Select restart/configure PostgreSQL
```

**Expected output on health check failure:**
```
Verifying PostgreSQL health...
⚠️  Health check failed: [error message]
💾 Diagnostics saved to: /tmp/platform-diagnostics-YYYYMMDD-HHMMSS.log
   Continuing setup...
```

**Key validation points:**
- [x] Warning symbol appears (⚠️)
- [x] Error message is descriptive
- [x] Diagnostics are saved to timestamped file
- [x] Setup continues (non-blocking)
- [x] Diagnostic file contains useful debugging information

### Success Criteria

- [ ] Health check runs automatically after successful PostgreSQL installation
- [ ] Detailed metrics displayed on success (database count, version)
- [ ] Failure handling is graceful and non-blocking
- [ ] Diagnostics are saved to file on failure
- [ ] User experience is smooth and informative

### Notes

- This is a manual test because it requires running the wizard interactively
- Health check integration is non-blocking: failures don't stop wizard progress
- Diagnostic files are saved to /tmp with timestamps for easy identification
