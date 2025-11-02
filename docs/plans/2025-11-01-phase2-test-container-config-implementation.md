# Phase 2: Test Container Configuration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development for parallel TDD execution.

**Goal:** Add wizard configuration for PostgreSQL and SQL Server test containers, supporting both build-from-base and prebuilt image modes for corporate environments.

**Architecture:** Move test container Dockerfiles from kerberos/ to platform-infrastructure/ (proper ownership), create wizard sub-spec following Kerberos pattern (IMAGE + PREBUILT boolean), implement build targets supporting both modes, update documentation to clarify architecture layers.

**Tech Stack:** Python (wizard), YAML (specs), Bash/Make (build), Docker (containers), pytest (testing)

**Execution Model:** Each task has Red/Green/Review sub-phases executed in parallel worktrees inheriting from master PR branch `feature/test-container-config`.

---

## Task 1: Create Test Container Dockerfiles

**Worktrees:**
- `.worktrees/task-1-dockerfiles` (inherits from `feature/test-container-config`)

**Sub-phases:**
- Task 1a (Red): Verify old Dockerfiles exist, plan migration
- Task 1b (Green): Create new Dockerfiles with refactoring
- Task 1c (Review): Code review + verify builds work

**Files:**
- Create: `platform-infrastructure/test-containers/postgres-test/Dockerfile`
- Create: `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`

**Step 1: Create directory structure**

```bash
mkdir -p platform-infrastructure/test-containers/postgres-test
mkdir -p platform-infrastructure/test-containers/sqlcmd-test
```

**Step 2: Move and refactor postgres-test Dockerfile**

Create `platform-infrastructure/test-containers/postgres-test/Dockerfile`:

```dockerfile
# PostgreSQL Test Image with psql and Kerberos
# ==============================================
# Minimal image for PostgreSQL GSSAPI authentication testing
# Build once, use many times - no runtime dependencies needed
#
# Purpose:
#   Test PostgreSQL GSSAPI authentication using tickets from Kerberos sidecar.
#   This container is SEPARATE from the sidecar - it mounts the sidecar's ticket
#   volume to connect to PostgreSQL using Kerberos authentication.
#
# Build:
#   docker build -f Dockerfile \
#     --build-arg BASE_IMAGE=alpine:latest \
#     -t platform/postgres-test:latest .
#
# Usage with Kerberos Sidecar:
#   docker run --rm \
#     -v kerberos-tickets:/krb5/cache:ro \
#     -v /path/to/krb5.conf:/etc/krb5.conf:ro \
#     -e KRB5CCNAME=/krb5/cache/krb5cc \
#     -e PGHOST=postgres.example.com \
#     -e PGDATABASE=mydb \
#     -e PGUSER=myuser \
#     platform/postgres-test:latest \
#     -c "psql -c 'SELECT version();'"

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install PostgreSQL client with GSSAPI + Kerberos tools + ODBC
RUN apk update && apk add --no-cache \
    postgresql17-client \
    krb5 krb5-libs krb5-conf \
    unixodbc unixodbc-dev \
    ca-certificates tzdata \
    && echo "✓ PostgreSQL client and Kerberos installed successfully"

# Create non-root user
RUN adduser -D -u 10001 testuser

# Setup directories for psql and Kerberos config
RUN mkdir -p /home/testuser/.postgresql && \
    chmod 700 /home/testuser/.postgresql && \
    chown -R testuser:testuser /home/testuser

# Switch to non-root user
USER testuser

# Verify installation
RUN psql --version && klist -V

# Default entrypoint for testing
ENTRYPOINT ["/bin/sh"]
```

**Step 3: Move and refactor sqlcmd-test Dockerfile**

Create `platform-infrastructure/test-containers/sqlcmd-test/Dockerfile`:

```dockerfile
# SQL Server Test Image with Microsoft sqlcmd
# ============================================
# Minimal image with Microsoft ODBC Driver and sqlcmd for SQL Server testing
# Build once, use many times - no runtime downloads needed
#
# EULA Acceptance:
#   This image includes Microsoft ODBC Driver 18 for SQL Server (msodbcsql18)
#   and Microsoft SQL Server Tools (mssql-tools18). By setting ACCEPT_EULA=Y,
#   we accept the Microsoft ODBC Driver and SQL Server Tools license terms.
#   See: https://aka.ms/odbc18-eula
#
# Build:
#   docker build -f Dockerfile \
#     --build-arg BASE_IMAGE=alpine:latest \
#     -t platform/sqlcmd-test:latest .
#
# Corporate Environments:
#   If download.microsoft.com is blocked, prebuild this image in your
#   corporate registry and use prebuilt mode in the wizard.
#
# Usage with Kerberos Sidecar:
#   docker run --rm \
#     -v kerberos-tickets:/krb5/cache:ro \
#     -v /path/to/krb5.conf:/etc/krb5.conf:ro \
#     -e KRB5CCNAME=/krb5/cache/krb5cc \
#     platform/sqlcmd-test:latest \
#     -c "sqlcmd -S sqlserver.example.com -E -Q 'SELECT @@VERSION'"

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Accept Microsoft EULA for ODBC Driver 18 and SQL Server Tools 18
# Required for installation of msodbcsql18 and mssql-tools18 packages
# License: https://aka.ms/odbc18-eula
ENV ACCEPT_EULA=Y

# Install Kerberos, ODBC infrastructure, and FreeTDS
RUN apk update && apk add --no-cache \
    krb5 krb5-libs krb5-conf \
    ca-certificates tzdata \
    curl \
    unixodbc unixodbc-dev \
    freetds freetds-dev \
    && echo "✓ Kerberos, ODBC, and FreeTDS installed successfully"

# Install Microsoft SQL Server tools from public source
# Corporate environments: Use prebuilt images if download.microsoft.com is blocked
RUN arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    base_url="https://download.microsoft.com/download/7/6/d/76de322a-d860-4894-9945-f0cc5d6a45f8" && \
    cd /tmp && \
    echo "Downloading Microsoft ODBC driver..." && \
    curl -fsSL -o msodbc.apk "${base_url}/msodbcsql18_18.4.1.1-1_${arch}.apk" && \
    echo "Downloading Microsoft SQL tools..." && \
    curl -fsSL -o mssql-tools.apk "${base_url}/mssql-tools18_18.4.1.1-1_${arch}.apk" && \
    echo "Installing Microsoft packages..." && \
    apk add --allow-untrusted msodbc.apk mssql-tools.apk && \
    rm -f *.apk && \
    echo "✓ Microsoft SQL tools installed successfully"

# Add sqlcmd to PATH
ENV PATH="/opt/mssql-tools18/bin:${PATH}"

# Create non-root user
RUN adduser -D -u 10001 testuser

# Switch to non-root user
USER testuser

# Verify installation
RUN sqlcmd -? > /dev/null && odbcinst -q -d && klist -V

# Default entrypoint for testing
ENTRYPOINT ["/bin/sh"]
```

**Step 4: Commit the Dockerfile creation**

```bash
git add platform-infrastructure/test-containers/
git commit -m "feat: Add test container Dockerfiles to platform-infrastructure

Move test container Dockerfiles from kerberos/kerberos-sidecar/ to
platform-infrastructure/test-containers/ to reflect proper ownership.

Changes:
- postgres-test: Add BASE_IMAGE arg, add unixODBC, add non-root user
- sqlcmd-test: Add BASE_IMAGE arg, remove MSSQL_TOOLS_URL, add non-root user
- Both: Use alpine:latest as default base with package installs

Test containers are base platform infrastructure, not Kerberos-owned."
```

---

## Task 2: Create Wizard Sub-Spec for Test Containers

**Files:**
- Create: `wizard/services/base_platform/test-containers-spec.yaml`

**Step 1: Write the sub-spec YAML**

Create `wizard/services/base_platform/test-containers-spec.yaml`:

```yaml
# Test Container Configuration Sub-Spec
# ======================================
# Configures PostgreSQL and SQL Server test containers for connectivity testing
# Invoked from main base_platform/spec.yaml after postgres setup
#
# Follows Kerberos pattern: IMAGE + PREBUILT boolean
# - IMAGE: Base to build from OR prebuilt image path
# - PREBUILT: false = build from base, true = use as-is

service: base_platform
sub_spec: test_containers
version: "1.0"
description: "Test container configuration for PostgreSQL and SQL Server connectivity testing"

steps:
  - id: postgres_test_prebuilt
    type: boolean
    state_key: services.base_platform.test_containers.postgres_test.prebuilt
    default_from: services.base_platform.test_containers.postgres_test.prebuilt
    prompt: "Use prebuilt PostgreSQL test image (vs. building from base)?"
    default_value: false
    help: "If false, we build from the base image you specify. If true, we use the image as-is."
    next: postgres_test_image

  - id: postgres_test_image
    type: string
    state_key: services.base_platform.test_containers.postgres_test.image
    default_from: services.base_platform.test_containers.postgres_test.image
    prompt: "PostgreSQL test container image:"
    default_value: "alpine:latest"
    help: "If building: base image (e.g., alpine:latest, cgr.dev/chainguard/wolfi-base). If prebuilt: full path (e.g., mycorp.io/postgres-test:v1)"
    validator: base_platform.validate_image_url
    next: sqlcmd_test_prebuilt

  - id: sqlcmd_test_prebuilt
    type: boolean
    state_key: services.base_platform.test_containers.sqlcmd_test.prebuilt
    default_from: services.base_platform.test_containers.sqlcmd_test.prebuilt
    prompt: "Use prebuilt SQL Server test image (vs. building from base)?"
    default_value: false
    help: "If false, we build from the base image you specify. If true, we use the image as-is."
    next: sqlcmd_test_image

  - id: sqlcmd_test_image
    type: string
    state_key: services.base_platform.test_containers.sqlcmd_test.image
    default_from: services.base_platform.test_containers.sqlcmd_test.image
    prompt: "SQL Server test container image:"
    default_value: "alpine:latest"
    help: "If building: base image (e.g., alpine:latest). If prebuilt: full path (e.g., mycorp.io/sqlcmd-test:v1). Note: Building downloads from Microsoft (blocked in some corporate networks)."
    validator: base_platform.validate_image_url
    next: save_test_config

  - id: save_test_config
    type: action
    action: base_platform.save_test_container_config
    next: finish
```

**Step 2: Commit the sub-spec**

```bash
git add wizard/services/base_platform/test-containers-spec.yaml
git commit -m "feat: Add test-containers wizard sub-spec

Create wizard sub-spec for test container configuration following
the established Kerberos pattern (IMAGE + PREBUILT boolean).

Configuration:
- postgres_test.image + postgres_test.prebuilt
- sqlcmd_test.image + sqlcmd_test.prebuilt

Saved to platform-config.yaml and platform-bootstrap/.env"
```

---

## Task 3: Implement Wizard Actions

**Files:**
- Modify: `wizard/services/base_platform/actions.py`

**Step 1: Add import for sub-spec loading**

In `wizard/services/base_platform/actions.py`, add to imports section:

```python
from wizard.core.spec_loader import load_spec
```

**Step 2: Add action to invoke test-containers sub-spec**

Add this function to `wizard/services/base_platform/actions.py`:

```python
def invoke_test_container_spec(state, console):
    """
    Invoke the test-containers sub-spec to configure test containers.

    The sub-spec prompts for:
    - PostgreSQL test container configuration (prebuilt flag + image)
    - SQL Server test container configuration (prebuilt flag + image)

    Configuration is saved via save_test_container_config action.
    """
    from wizard.core.wizard_engine import WizardEngine
    import os

    # Load test-containers sub-spec
    spec_dir = os.path.dirname(os.path.abspath(__file__))
    spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")

    if not os.path.exists(spec_path):
        console.print(f"[red]Error: Test containers sub-spec not found at {spec_path}[/red]")
        return False

    sub_spec = load_spec(spec_path)
    if not sub_spec:
        console.print("[red]Error: Failed to load test-containers sub-spec[/red]")
        return False

    # Execute sub-spec
    engine = WizardEngine(state, console)
    success = engine.execute_spec(sub_spec)

    if not success:
        console.print("[red]Test container configuration incomplete[/red]")
        return False

    console.print("[green]✓ Test container configuration complete[/green]")
    return True
```

**Step 3: Add action to save test container config**

Add this function to `wizard/services/base_platform/actions.py`:

```python
def save_test_container_config(state, console):
    """
    Save test container configuration to platform-config.yaml and .env

    Reads configuration from state:
    - services.base_platform.test_containers.postgres_test.image
    - services.base_platform.test_containers.postgres_test.prebuilt
    - services.base_platform.test_containers.sqlcmd_test.image
    - services.base_platform.test_containers.sqlcmd_test.prebuilt

    Writes to:
    - platform-config.yaml (nested under services.base_platform.test_containers)
    - platform-bootstrap/.env (IMAGE_POSTGRES_TEST, POSTGRES_TEST_PREBUILT, etc.)
    """
    from wizard.utils.config import save_config_value, save_env_value

    # Get test container configuration from state
    postgres_test_config = state.get("services.base_platform.test_containers.postgres_test", {})
    sqlcmd_test_config = state.get("services.base_platform.test_containers.sqlcmd_test", {})

    postgres_image = postgres_test_config.get("image", "alpine:latest")
    postgres_prebuilt = postgres_test_config.get("prebuilt", False)

    sqlcmd_image = sqlcmd_test_config.get("image", "alpine:latest")
    sqlcmd_prebuilt = sqlcmd_test_config.get("prebuilt", False)

    # Save to platform-config.yaml
    save_config_value("services.base_platform.test_containers.postgres_test.image", postgres_image)
    save_config_value("services.base_platform.test_containers.postgres_test.prebuilt", postgres_prebuilt)
    save_config_value("services.base_platform.test_containers.sqlcmd_test.image", sqlcmd_image)
    save_config_value("services.base_platform.test_containers.sqlcmd_test.prebuilt", sqlcmd_prebuilt)

    # Save to platform-bootstrap/.env
    save_env_value("IMAGE_POSTGRES_TEST", postgres_image)
    save_env_value("POSTGRES_TEST_PREBUILT", "true" if postgres_prebuilt else "false")
    save_env_value("IMAGE_SQLCMD_TEST", sqlcmd_image)
    save_env_value("SQLCMD_TEST_PREBUILT", "true" if sqlcmd_prebuilt else "false")

    console.print(f"[green]✓ Saved test container configuration:[/green]")
    console.print(f"  PostgreSQL test: {postgres_image} (prebuilt={postgres_prebuilt})")
    console.print(f"  SQL Server test: {sqlcmd_image} (prebuilt={sqlcmd_prebuilt})")

    return True
```

**Step 4: Commit the action implementations**

```bash
git add wizard/services/base_platform/actions.py
git commit -m "feat: Add test container wizard actions

Implement two actions:
- invoke_test_container_spec: Load and execute test-containers sub-spec
- save_test_container_config: Save configuration to platform-config.yaml and .env

Configuration follows Kerberos pattern (IMAGE + PREBUILT boolean)."
```

---

## Task 4: Integrate Test Container Config into Main Spec

**Files:**
- Modify: `wizard/services/base_platform/spec.yaml`

**Step 1: Add test container configuration step**

In `wizard/services/base_platform/spec.yaml`, find the `postgres_start` step and update its `next` field:

Change from:
```yaml
  - id: postgres_start
    type: action
    action: base_platform.start_service
    next: finish
```

To:
```yaml
  - id: postgres_start
    type: action
    action: base_platform.start_service
    next: configure_test_containers

  - id: configure_test_containers
    type: action
    action: base_platform.invoke_test_container_spec
    next: finish
```

**Step 2: Commit the spec integration**

```bash
git add wizard/services/base_platform/spec.yaml
git commit -m "feat: Integrate test container config into base_platform setup

Add configure_test_containers step after postgres_start to invoke
test-containers sub-spec. Users now configure test containers as part
of base_platform setup flow."
```

---

## Task 5: Add Makefile Build Targets

**Files:**
- Modify: `Makefile` (root)

**Step 1: Add build-postgres-test target**

Add this target to the root `Makefile`:

```makefile
.PHONY: build-postgres-test
build-postgres-test:  ## Build PostgreSQL test container (or pull prebuilt)
	@source platform-bootstrap/.env 2>/dev/null || true && \
	if [ "$${POSTGRES_TEST_PREBUILT}" = "true" ]; then \
		echo "Using prebuilt image: $${IMAGE_POSTGRES_TEST}"; \
		docker pull $${IMAGE_POSTGRES_TEST} && \
		docker tag $${IMAGE_POSTGRES_TEST} platform/postgres-test:latest; \
	else \
		echo "Building postgres-test from base: $${IMAGE_POSTGRES_TEST:-alpine:latest}"; \
		docker build \
		  -f platform-infrastructure/test-containers/postgres-test/Dockerfile \
		  --build-arg BASE_IMAGE=$${IMAGE_POSTGRES_TEST:-alpine:latest} \
		  -t platform/postgres-test:latest \
		  platform-infrastructure/test-containers/postgres-test/; \
	fi
```

**Step 2: Add build-sqlcmd-test target**

Add this target to the root `Makefile`:

```makefile
.PHONY: build-sqlcmd-test
build-sqlcmd-test:  ## Build SQL Server test container (or pull prebuilt)
	@source platform-bootstrap/.env 2>/dev/null || true && \
	if [ "$${SQLCMD_TEST_PREBUILT}" = "true" ]; then \
		echo "Using prebuilt image: $${IMAGE_SQLCMD_TEST}"; \
		docker pull $${IMAGE_SQLCMD_TEST} && \
		docker tag $${IMAGE_SQLCMD_TEST} platform/sqlcmd-test:latest; \
	else \
		echo "Building sqlcmd-test from base: $${IMAGE_SQLCMD_TEST:-alpine:latest}"; \
		docker build \
		  -f platform-infrastructure/test-containers/sqlcmd-test/Dockerfile \
		  --build-arg BASE_IMAGE=$${IMAGE_SQLCMD_TEST:-alpine:latest} \
		  -t platform/sqlcmd-test:latest \
		  platform-infrastructure/test-containers/sqlcmd-test/; \
	fi
```

**Step 3: Add combined build-test-containers target**

Add this convenience target to the root `Makefile`:

```makefile
.PHONY: build-test-containers
build-test-containers: build-postgres-test build-sqlcmd-test  ## Build all test containers
```

**Step 4: Commit the Makefile targets**

```bash
git add Makefile
git commit -m "feat: Add Makefile targets for test containers

Add build targets:
- build-postgres-test: Build or pull postgres test container
- build-sqlcmd-test: Build or pull sqlcmd test container
- build-test-containers: Build both

Targets read configuration from platform-bootstrap/.env and handle
both build-from-base and prebuilt modes."
```

---

## Task 6: Update Environment Configuration Example

**Files:**
- Modify: `platform-bootstrap/.env.example`

**Step 1: Add test container configuration section**

Add this section to `platform-bootstrap/.env.example` (after existing PostgreSQL configuration):

```bash
# ==========================================
# Test Containers (Base Platform)
# ==========================================
# Lightweight test containers for connectivity validation
# These are ephemeral - run on-demand for testing, not deployed to production
#
# PostgreSQL test container (postgres-test)
# - Purpose: PostgreSQL GSSAPI authentication testing
# - Size: ~50 MB
# - Contents: postgresql-client, krb5, unixODBC
#
# SQL Server test container (sqlcmd-test)
# - Purpose: SQL Server Kerberos authentication testing
# - Size: ~100 MB
# - Contents: Microsoft ODBC Driver, sqlcmd, FreeTDS, krb5
#
# Configuration follows Kerberos pattern (IMAGE + PREBUILT):
# - IMAGE: Base to build from OR prebuilt image path
# - PREBUILT: false = build from base, true = use as-is

# PostgreSQL test container
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false

# SQL Server test container
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false

# Example corporate configurations:
#
# Build from approved base image:
# IMAGE_POSTGRES_TEST=mycorp.jfrog.io/approved/alpine:3.22
# POSTGRES_TEST_PREBUILT=false
#
# Use prebuilt corporate image:
# IMAGE_SQLCMD_TEST=mycorp.jfrog.io/test-images/sqlcmd-test:v1
# SQLCMD_TEST_PREBUILT=true
```

**Step 2: Commit the .env.example update**

```bash
git add platform-bootstrap/.env.example
git commit -m "docs: Add test container configuration to .env.example

Document IMAGE_POSTGRES_TEST, POSTGRES_TEST_PREBUILT,
IMAGE_SQLCMD_TEST, SQLCMD_TEST_PREBUILT environment variables.

Includes examples for both build-from-base and prebuilt modes."
```

---

## Task 7: Write Tests for Test Container Configuration

**Files:**
- Create: `wizard/services/base_platform/tests/test_test_containers_spec.py`
- Create: `wizard/services/base_platform/tests/test_test_containers_actions.py`

**Step 1: Write the failing test for sub-spec loading**

Create `wizard/services/base_platform/tests/test_test_containers_spec.py`:

```python
"""Tests for test-containers sub-spec"""
import os
import pytest
from wizard.core.spec_loader import load_spec


class TestTestContainersSpecLoads:
    """Verify test-containers sub-spec loads correctly"""

    def test_sub_spec_file_exists(self):
        """Verify test-containers-spec.yaml exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        assert os.path.exists(spec_path), f"Sub-spec not found at {spec_path}"

    def test_sub_spec_loads(self):
        """Verify test-containers sub-spec loads without errors"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)
        assert spec is not None, "Failed to load test-containers sub-spec"

    def test_sub_spec_has_required_fields(self):
        """Verify sub-spec has required fields"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        assert "service" in spec, "Missing 'service' field"
        assert spec["service"] == "base_platform", "Wrong service name"

        assert "sub_spec" in spec, "Missing 'sub_spec' field"
        assert spec["sub_spec"] == "test_containers", "Wrong sub_spec name"

        assert "version" in spec, "Missing 'version' field"
        assert "description" in spec, "Missing 'description' field"
        assert "steps" in spec, "Missing 'steps' field"


class TestTestContainersSpecSteps:
    """Verify test-containers sub-spec steps are valid"""

    def test_has_postgres_test_prebuilt_step(self):
        """Verify postgres_test_prebuilt boolean step exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        steps = {step["id"]: step for step in spec["steps"]}
        assert "postgres_test_prebuilt" in steps, "Missing postgres_test_prebuilt step"

        step = steps["postgres_test_prebuilt"]
        assert step["type"] == "boolean", "Wrong type for postgres_test_prebuilt"
        assert step["state_key"] == "services.base_platform.test_containers.postgres_test.prebuilt"

    def test_has_postgres_test_image_step(self):
        """Verify postgres_test_image string step exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        steps = {step["id"]: step for step in spec["steps"]}
        assert "postgres_test_image" in steps, "Missing postgres_test_image step"

        step = steps["postgres_test_image"]
        assert step["type"] == "string", "Wrong type for postgres_test_image"
        assert step["state_key"] == "services.base_platform.test_containers.postgres_test.image"
        assert step["default_value"] == "alpine:latest"

    def test_has_sqlcmd_test_prebuilt_step(self):
        """Verify sqlcmd_test_prebuilt boolean step exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        steps = {step["id"]: step for step in spec["steps"]}
        assert "sqlcmd_test_prebuilt" in steps, "Missing sqlcmd_test_prebuilt step"

        step = steps["sqlcmd_test_prebuilt"]
        assert step["type"] == "boolean", "Wrong type for sqlcmd_test_prebuilt"
        assert step["state_key"] == "services.base_platform.test_containers.sqlcmd_test.prebuilt"

    def test_has_sqlcmd_test_image_step(self):
        """Verify sqlcmd_test_image string step exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        steps = {step["id"]: step for step in spec["steps"]}
        assert "sqlcmd_test_image" in steps, "Missing sqlcmd_test_image step"

        step = steps["sqlcmd_test_image"]
        assert step["type"] == "string", "Wrong type for sqlcmd_test_image"
        assert step["state_key"] == "services.base_platform.test_containers.sqlcmd_test.image"
        assert step["default_value"] == "alpine:latest"

    def test_has_save_config_action_step(self):
        """Verify save_test_config action step exists"""
        spec_dir = os.path.join("wizard", "services", "base_platform")
        spec_path = os.path.join(spec_dir, "test-containers-spec.yaml")
        spec = load_spec(spec_path)

        steps = {step["id"]: step for step in spec["steps"]}
        assert "save_test_config" in steps, "Missing save_test_config step"

        step = steps["save_test_config"]
        assert step["type"] == "action", "Wrong type for save_test_config"
        assert step["action"] == "base_platform.save_test_container_config"
```

**Step 2: Run tests to verify they pass**

```bash
python -m pytest wizard/services/base_platform/tests/test_test_containers_spec.py -v
```

Expected: All tests PASS (sub-spec already created in Task 2)

**Step 3: Write tests for action implementations**

Create `wizard/services/base_platform/tests/test_test_containers_actions.py`:

```python
"""Tests for test container configuration actions"""
import pytest
from unittest.mock import Mock, patch, MagicMock
from wizard.services.base_platform import actions


class TestInvokeTestContainerSpec:
    """Tests for invoke_test_container_spec action"""

    def test_action_exists(self):
        """Verify invoke_test_container_spec function exists"""
        assert hasattr(actions, "invoke_test_container_spec")
        assert callable(actions.invoke_test_container_spec)

    @patch("wizard.services.base_platform.actions.load_spec")
    @patch("wizard.services.base_platform.actions.WizardEngine")
    def test_loads_and_executes_sub_spec(self, mock_engine_class, mock_load_spec):
        """Verify action loads and executes test-containers sub-spec"""
        # Setup mocks
        mock_spec = {"service": "base_platform", "sub_spec": "test_containers", "steps": []}
        mock_load_spec.return_value = mock_spec

        mock_engine = Mock()
        mock_engine.execute_spec.return_value = True
        mock_engine_class.return_value = mock_engine

        state = {}
        console = Mock()

        # Execute
        result = actions.invoke_test_container_spec(state, console)

        # Verify
        assert result is True
        mock_load_spec.assert_called_once()
        mock_engine.execute_spec.assert_called_once_with(mock_spec)

    @patch("wizard.services.base_platform.actions.load_spec")
    def test_returns_false_if_spec_not_found(self, mock_load_spec):
        """Verify action returns False if sub-spec file not found"""
        mock_load_spec.return_value = None

        state = {}
        console = Mock()

        result = actions.invoke_test_container_spec(state, console)

        assert result is False


class TestSaveTestContainerConfig:
    """Tests for save_test_container_config action"""

    def test_action_exists(self):
        """Verify save_test_container_config function exists"""
        assert hasattr(actions, "save_test_container_config")
        assert callable(actions.save_test_container_config)

    @patch("wizard.services.base_platform.actions.save_config_value")
    @patch("wizard.services.base_platform.actions.save_env_value")
    def test_saves_postgres_test_config(self, mock_save_env, mock_save_config):
        """Verify action saves postgres_test configuration"""
        state = {
            "services": {
                "base_platform": {
                    "test_containers": {
                        "postgres_test": {
                            "image": "alpine:3.22",
                            "prebuilt": False
                        }
                    }
                }
            }
        }
        console = Mock()

        result = actions.save_test_container_config(state, console)

        assert result is True

        # Verify platform-config.yaml saves
        mock_save_config.assert_any_call(
            "services.base_platform.test_containers.postgres_test.image",
            "alpine:3.22"
        )
        mock_save_config.assert_any_call(
            "services.base_platform.test_containers.postgres_test.prebuilt",
            False
        )

        # Verify .env saves
        mock_save_env.assert_any_call("IMAGE_POSTGRES_TEST", "alpine:3.22")
        mock_save_env.assert_any_call("POSTGRES_TEST_PREBUILT", "false")

    @patch("wizard.services.base_platform.actions.save_config_value")
    @patch("wizard.services.base_platform.actions.save_env_value")
    def test_saves_sqlcmd_test_config(self, mock_save_env, mock_save_config):
        """Verify action saves sqlcmd_test configuration"""
        state = {
            "services": {
                "base_platform": {
                    "test_containers": {
                        "sqlcmd_test": {
                            "image": "mycorp.io/sqlcmd-test:v1",
                            "prebuilt": True
                        }
                    }
                }
            }
        }
        console = Mock()

        result = actions.save_test_container_config(state, console)

        assert result is True

        # Verify platform-config.yaml saves
        mock_save_config.assert_any_call(
            "services.base_platform.test_containers.sqlcmd_test.image",
            "mycorp.io/sqlcmd-test:v1"
        )
        mock_save_config.assert_any_call(
            "services.base_platform.test_containers.sqlcmd_test.prebuilt",
            True
        )

        # Verify .env saves
        mock_save_env.assert_any_call("IMAGE_SQLCMD_TEST", "mycorp.io/sqlcmd-test:v1")
        mock_save_env.assert_any_call("SQLCMD_TEST_PREBUILT", "true")

    @patch("wizard.services.base_platform.actions.save_config_value")
    @patch("wizard.services.base_platform.actions.save_env_value")
    def test_uses_defaults_if_not_configured(self, mock_save_env, mock_save_config):
        """Verify action uses defaults if test containers not configured"""
        state = {}
        console = Mock()

        result = actions.save_test_container_config(state, console)

        assert result is True

        # Verify defaults used
        mock_save_env.assert_any_call("IMAGE_POSTGRES_TEST", "alpine:latest")
        mock_save_env.assert_any_call("POSTGRES_TEST_PREBUILT", "false")
        mock_save_env.assert_any_call("IMAGE_SQLCMD_TEST", "alpine:latest")
        mock_save_env.assert_any_call("SQLCMD_TEST_PREBUILT", "false")
```

**Step 4: Run tests to verify they pass**

```bash
python -m pytest wizard/services/base_platform/tests/test_test_containers_actions.py -v
```

Expected: All tests PASS (actions already implemented in Task 3)

**Step 5: Run all base_platform tests to verify nothing broke**

```bash
python -m pytest wizard/services/base_platform/tests/ -v
```

Expected: All tests PASS (including 102 original + new test container tests)

**Step 6: Commit the tests**

```bash
git add wizard/services/base_platform/tests/test_test_containers_spec.py
git add wizard/services/base_platform/tests/test_test_containers_actions.py
git commit -m "test: Add comprehensive tests for test container configuration

Add test coverage for:
- test-containers-spec.yaml loading and structure
- invoke_test_container_spec action
- save_test_container_config action

All tests passing."
```

---

## Task 8: Update Documentation - directory-structure.md

**Files:**
- Modify: `docs/directory-structure.md`

**Step 1: Add architecture layers explanation**

Add this section after the "Repository Root" section in `docs/directory-structure.md`:

```markdown
## 🏗️ Architecture Layers

The platform has two distinct architectural layers that must be clearly separated:

### Configuration Layer (Wizard)
**Location**: `wizard/services/`
**Purpose**: User-facing prompts, validation, state management
**Outputs**: `platform-config.yaml`, `platform-bootstrap/.env`
**Responsibility**: Captures what the user wants configured

### Runtime/Operational Layer
**Location**: `platform-infrastructure/`
**Purpose**: Actual running services, Dockerfiles, compose files, build artifacts
**Inputs**: Configuration from `platform-bootstrap/.env`
**Responsibility**: Implements how services actually run

**Why This Matters:**
This separation ensures configuration (what user wants) stays separate from implementation (how services run). Test containers are runtime artifacts, so they belong in `platform-infrastructure/`, not with the services that consume them.
```

**Step 2: Add platform-infrastructure section**

Add this section to the "Core Platform Components" area:

```markdown
### `platform-infrastructure/`
**Purpose**: Runtime services and containers for platform operations

```
platform-infrastructure/
├── postgres/
│   └── init-databases.sh          # Database initialization
├── test-containers/                 # Test containers for connectivity validation
│   ├── postgres-test/
│   │   └── Dockerfile              # PostgreSQL GSSAPI test container
│   └── sqlcmd-test/
│       └── Dockerfile              # SQL Server Kerberos test container
├── docker-compose.yml              # Platform services composition
├── Makefile                        # Service management commands
└── README.md                       # Infrastructure documentation
```

**Test Containers:**
- `postgres-test`: PostgreSQL GSSAPI authentication testing (~50 MB)
- `sqlcmd-test`: SQL Server Kerberos authentication testing (~100 MB)
- Ephemeral - run on-demand for testing, not deployed to production
- Configured via wizard, built via Makefile targets
```

**Step 3: Add wizard section**

Add this section to the "Core Platform Components" area:

```markdown
### `wizard/`
**Purpose**: Interactive configuration wizard for platform setup

```
wizard/
├── services/                       # Service configuration modules
│   ├── base_platform/             # PostgreSQL + test containers config
│   │   ├── spec.yaml              # Main configuration flow
│   │   ├── test-containers-spec.yaml  # Test container sub-spec
│   │   ├── actions.py             # Configuration actions
│   │   ├── validators.py          # Input validation
│   │   └── tests/                 # Service tests
│   ├── kerberos/                  # Kerberos configuration
│   ├── openmetadata/              # OpenMetadata configuration
│   └── ...
├── core/                          # Wizard engine and utilities
├── flows/                         # Multi-service setup flows
└── utils/                         # Shared utilities
```

**Wizard Pattern:**
Configuration is captured in wizard, saved to `platform-config.yaml` and `platform-bootstrap/.env`, then consumed by platform-infrastructure for actual service deployment.
```

**Step 4: Update "Finding What You Need" table**

Update the table in `docs/directory-structure.md`:

```markdown
| If you're looking for... | Look in... |
|-------------------------|------------|
| SQLModel table patterns | `sqlmodel-framework/` |
| Container base images | `runtime-environments/` |
| Developer setup | `platform-bootstrap/` |
| Running services, Dockerfiles | `platform-infrastructure/` |
| Service configuration | `wizard/services/` |
| Documentation | `docs/` |
| Utility scripts | `scripts/` |
```

**Step 5: Commit documentation updates**

```bash
git add docs/directory-structure.md
git commit -m "docs: Add architecture layers and missing directories

Add architecture layer explanation:
- Configuration Layer (wizard) vs Runtime Layer (platform-infrastructure)
- Why separation matters for ownership and responsibility

Add missing directory sections:
- platform-infrastructure/ (runtime services, test containers)
- wizard/ (interactive configuration)

Update navigation table with new locations."
```

---

## Task 9: Update Documentation - platform-infrastructure/README.md

**Files:**
- Modify: `platform-infrastructure/README.md`

**Step 1: Add test containers section**

Add this section after the "Quick Start" section in `platform-infrastructure/README.md`:

```markdown
## Test Containers

Platform infrastructure includes lightweight test containers for connectivity validation:

### postgres-test
- **Purpose**: PostgreSQL GSSAPI authentication testing
- **Size**: ~50 MB
- **Contents**: postgresql-client, krb5, unixODBC
- **Build**: `make build-postgres-test` (from repo root)
- **Usage**: Mount Kerberos ticket cache, run psql commands

```bash
# Example: Test PostgreSQL GSSAPI connection
docker run --rm \
  -v kerberos-tickets:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  -e PGHOST=postgres.example.com \
  -e PGDATABASE=mydb \
  -e PGUSER=myuser \
  platform/postgres-test:latest \
  -c "psql -c 'SELECT version();'"
```

### sqlcmd-test
- **Purpose**: SQL Server Kerberos authentication testing
- **Size**: ~100 MB
- **Contents**: Microsoft ODBC Driver, sqlcmd, FreeTDS, krb5
- **Build**: `make build-sqlcmd-test` (from repo root)
- **Usage**: Mount Kerberos ticket cache, run sqlcmd commands

```bash
# Example: Test SQL Server Kerberos connection
docker run --rm \
  -v kerberos-tickets:/krb5/cache:ro \
  -v $(pwd)/krb5.conf:/etc/krb5.conf:ro \
  -e KRB5CCNAME=/krb5/cache/krb5cc \
  platform/sqlcmd-test:latest \
  -c "sqlcmd -S sqlserver.example.com -E -Q 'SELECT @@VERSION'"
```

### Configuration

Test containers are configured via the platform wizard during base_platform setup:

1. Run `./platform setup`
2. Configure base_platform (PostgreSQL)
3. Configure test containers:
   - Choose build-from-base or use-prebuilt for each container
   - Specify base image (if building) or prebuilt image path

Configuration saved to:
- `platform-config.yaml` (wizard state)
- `platform-bootstrap/.env` (runtime values)

### Build Modes

**Build from base** (default):
```bash
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
```
Builds from specified base image using Dockerfile.

**Use prebuilt**:
```bash
IMAGE_POSTGRES_TEST=mycorp.io/postgres-test:v1
POSTGRES_TEST_PREBUILT=true
```
Pulls and uses prebuilt image as-is (for corporate environments).

### Key Points

- Test containers are **ephemeral** - run on-demand for testing, not deployed to production
- They consume Kerberos tickets from the sidecar via shared volumes
- They are **separate from the sidecar** - follows single responsibility principle
- Corporate users can prebuild images if download.microsoft.com is blocked
```

**Step 2: Commit the README update**

```bash
git add platform-infrastructure/README.md
git commit -m "docs: Document test containers in platform-infrastructure README

Add comprehensive test containers documentation:
- Purpose and specs for postgres-test and sqlcmd-test
- Usage examples with Kerberos sidecar integration
- Configuration via wizard
- Build modes (build-from-base vs prebuilt)

Makes test container capabilities discoverable."
```

---

## Task 10: Integration Testing

**Files:**
- Create: `tests/integration/test_test_container_build.sh`

**Step 1: Write integration test script**

Create `tests/integration/test_test_container_build.sh`:

```bash
#!/bin/bash
# Integration test for test container build targets
# Tests both build-from-base and prebuilt modes

set -e

# Find repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Source formatting library
source "${REPO_ROOT}/platform-bootstrap/lib/formatting.sh"

print_header "Test Container Build Integration Test"

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Build postgres-test from default base
print_section "Test 1: Build postgres-test from alpine:latest"

cat > /tmp/test-containers.env <<EOF
IMAGE_POSTGRES_TEST=alpine:latest
POSTGRES_TEST_PREBUILT=false
EOF

source /tmp/test-containers.env
make build-postgres-test

if docker images | grep -q "platform/postgres-test.*latest"; then
    print_check "PASS" "postgres-test built successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "postgres-test not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify psql is present
if docker run --rm platform/postgres-test:latest -c "psql --version" | grep -q "psql"; then
    print_check "PASS" "psql command available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "psql command not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify klist is present
if docker run --rm platform/postgres-test:latest -c "klist -V" | grep -q "Kerberos"; then
    print_check "PASS" "Kerberos tools available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Kerberos tools not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Build sqlcmd-test from default base
print_section "Test 2: Build sqlcmd-test from alpine:latest"

cat > /tmp/test-containers.env <<EOF
IMAGE_SQLCMD_TEST=alpine:latest
SQLCMD_TEST_PREBUILT=false
EOF

source /tmp/test-containers.env
make build-sqlcmd-test

if docker images | grep -q "platform/sqlcmd-test.*latest"; then
    print_check "PASS" "sqlcmd-test built successfully"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "sqlcmd-test not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify sqlcmd is present
if docker run --rm platform/sqlcmd-test:latest -c "sqlcmd -?" 2>&1 | grep -q "sqlcmd"; then
    print_check "PASS" "sqlcmd command available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "sqlcmd command not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify odbcinst is present
if docker run --rm platform/sqlcmd-test:latest -c "odbcinst -q -d" 2>&1 | grep -q "ODBC"; then
    print_check "PASS" "ODBC tools available"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "ODBC tools not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Verify prebuilt mode (tag and use existing image)
print_section "Test 3: Verify prebuilt mode"

# Tag postgres-test as a "prebuilt" image
docker tag platform/postgres-test:latest test-prebuilt/postgres:v1

cat > /tmp/test-containers.env <<EOF
IMAGE_POSTGRES_TEST=test-prebuilt/postgres:v1
POSTGRES_TEST_PREBUILT=true
EOF

source /tmp/test-containers.env
make build-postgres-test

if docker images | grep -q "platform/postgres-test.*latest"; then
    print_check "PASS" "Prebuilt mode: postgres-test tagged correctly"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_check "FAIL" "Prebuilt mode: postgres-test not tagged"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Cleanup
rm -f /tmp/test-containers.env
docker rmi test-prebuilt/postgres:v1 2>/dev/null || true

# Report results
print_divider
print_section "Test Results"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    print_check "PASS" "All integration tests passed"
    exit 0
else
    print_check "FAIL" "Some integration tests failed"
    exit 1
fi
```

**Step 2: Make script executable**

```bash
chmod +x tests/integration/test_test_container_build.sh
```

**Step 3: Run integration tests**

```bash
./tests/integration/test_test_container_build.sh
```

Expected: All tests PASS

**Step 4: Commit the integration tests**

```bash
git add tests/integration/test_test_container_build.sh
git commit -m "test: Add integration tests for test container builds

Test coverage:
- Build postgres-test from alpine:latest base
- Build sqlcmd-test from alpine:latest base
- Verify tools present (psql, sqlcmd, klist, odbcinst)
- Verify prebuilt mode (pull and tag)

All tests passing."
```

---

## Task 11: Remove Old Test Container Dockerfiles

**Files:**
- Delete: `kerberos/kerberos-sidecar/Dockerfile.postgres-test`
- Delete: `kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test`

**Step 1: Verify new Dockerfiles work before removing old ones**

```bash
# Run integration tests one more time to be sure
./tests/integration/test_test_container_build.sh
```

Expected: All tests PASS

**Step 2: Remove old Dockerfiles**

```bash
git rm kerberos/kerberos-sidecar/Dockerfile.postgres-test
git rm kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test
```

**Step 3: Commit the removal**

```bash
git commit -m "refactor: Remove old test container Dockerfiles from kerberos/

Test containers have been moved to platform-infrastructure/test-containers/
where they belong (base platform infrastructure, not Kerberos-owned).

Old locations:
- kerberos/kerberos-sidecar/Dockerfile.postgres-test
- kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test

New locations:
- platform-infrastructure/test-containers/postgres-test/Dockerfile
- platform-infrastructure/test-containers/sqlcmd-test/Dockerfile

Integration tests confirm new Dockerfiles work correctly."
```

---

## Task 12: Final Verification

**Step 1: Run all base_platform tests**

```bash
python -m pytest wizard/services/base_platform/tests/ -v
```

Expected: All tests PASS (102 original + new test container tests)

**Step 2: Run integration tests**

```bash
./tests/integration/test_test_container_build.sh
```

Expected: All tests PASS

**Step 3: Verify build targets work**

```bash
make build-test-containers
```

Expected: Both containers build successfully

**Step 4: Verify wizard spec is valid**

```bash
python -c "from wizard.core.spec_loader import load_spec; spec = load_spec('wizard/services/base_platform/spec.yaml'); print('✓ Main spec valid')"
python -c "from wizard.core.spec_loader import load_spec; spec = load_spec('wizard/services/base_platform/test-containers-spec.yaml'); print('✓ Sub-spec valid')"
```

Expected: Both specs load without errors

**Step 5: Review git log**

```bash
git log --oneline origin/main..HEAD
```

Expected: Clean, descriptive commit messages for all changes

---

## Success Criteria

When all tasks complete:

- ✅ Test container Dockerfiles moved to platform-infrastructure/test-containers/
- ✅ Dockerfiles refactored (BASE_IMAGE, unixODBC, non-root users, no MSSQL_TOOLS_URL)
- ✅ Wizard sub-spec created following Kerberos pattern
- ✅ Wizard actions implemented (invoke_test_container_spec, save_test_container_config)
- ✅ Main spec updated to invoke test container configuration
- ✅ Makefile targets added (build-postgres-test, build-sqlcmd-test, build-test-containers)
- ✅ .env.example updated with test container configuration
- ✅ Documentation updated (directory-structure.md, platform-infrastructure/README.md)
- ✅ Comprehensive test coverage (unit, integration)
- ✅ All tests passing
- ✅ Old Dockerfiles removed from kerberos/
- ✅ Ready for PR creation

---

## Next Steps

After implementation:

1. Push branch: `git push origin feature/test-container-config`
2. Create PR: `gh pr create --base main --title "feat: Add test container configuration (Phase 2)"`
3. Request review
4. Address feedback
5. Merge to main
6. Use `./git-cleanup-audit.py` to clean up worktree after merge
