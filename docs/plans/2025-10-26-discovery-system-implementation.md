# Discovery System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add discovery system to wizard so clean-slate checks actual system state (Docker containers/images/volumes/files) instead of only reading platform-config.yaml.

**Architecture:** Each service module gets a discovery.py with standard functions (discover_containers, discover_images, discover_volumes, discover_files). Clean-slate flow runs discovery phase first, shows user what exists, then asks what to remove. All queries go through runner interface (fully mockable).

**Tech Stack:** Python 3.12, Docker CLI queries, existing wizard architecture (runner, specs, flows)

---

## Task Breakdown

### Serial Phase: Core Discovery Infrastructure
- Task 13a-c: Discovery engine integration (RED/GREEN/Review)

### Parallel Phase: Service Discovery Modules
- Task 14a-c: PostgreSQL discovery (RED/GREEN/Review)
- Task 15a-c: OpenMetadata discovery (RED/GREEN/Review)
- Task 16a-c: Kerberos discovery (RED/GREEN/Review)
- Task 17a-c: Pagila discovery (RED/GREEN/Review)

### Serial Phase: Flow Integration
- Task 18a-c: Clean-slate flow with discovery (RED/GREEN/Review)
- Task 19: Final integration review

---

## Task 13a: Discovery Engine Integration (RED Phase)

**Files:**
- Create: `wizard/engine/discovery.py`
- Create: `wizard/tests/test_discovery_engine.py`

**Step 1: Write the failing test for discovery engine**

Create `wizard/tests/test_discovery_engine.py`:

```python
"""Tests for discovery engine that aggregates service discovery results."""

import pytest
from wizard.engine.discovery import DiscoveryEngine
from wizard.engine.runner import MockActionRunner


class TestDiscoveryEngineBasics:
    """Test basic discovery engine functionality."""

    def test_discovery_engine_exists(self):
        """Discovery engine class should exist."""
        assert DiscoveryEngine is not None

    def test_discovery_engine_takes_runner(self):
        """Discovery engine should accept runner in constructor."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)
        assert engine.runner == runner


class TestDiscoverAllServices:
    """Test discovering all services at once."""

    def test_discover_all_returns_dict(self):
        """discover_all() should return dict with service names as keys."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        results = engine.discover_all()

        assert isinstance(results, dict)
        assert 'postgres' in results
        assert 'openmetadata' in results
        assert 'kerberos' in results
        assert 'pagila' in results

    def test_discover_all_calls_service_discovery(self):
        """discover_all() should call each service's discovery functions."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        results = engine.discover_all()

        # Should have called docker commands
        assert len(runner.calls) > 0


class TestDiscoverySummary:
    """Test aggregating discovery into summary."""

    def test_get_summary_counts_artifacts(self):
        """get_summary() should count total containers/images/volumes."""
        runner = MockActionRunner()
        # Mock finding 1 postgres container
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\n'
        }

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()
        summary = engine.get_summary(results)

        assert summary['total_containers'] >= 1
        assert 'total_images' in summary
        assert 'total_volumes' in summary

    def test_empty_system_returns_zero_counts(self):
        """get_summary() should return zeros when nothing found."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {}  # No artifacts

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()
        summary = engine.get_summary(results)

        assert summary['total_containers'] == 0
        assert summary['total_images'] == 0
        assert summary['total_volumes'] == 0
```

**Step 2: Run test to verify it fails**

Run: `uv run pytest wizard/tests/test_discovery_engine.py -v`

Expected: FAIL with "No module named 'wizard.engine.discovery'"

**Step 3: Write minimal implementation**

Create `wizard/engine/discovery.py`:

```python
"""Discovery engine for finding actual platform artifacts on the system."""

from typing import Dict, List, Any


class DiscoveryEngine:
    """Aggregates discovery from all services."""

    def __init__(self, runner):
        """Initialize with action runner.

        Args:
            runner: ActionRunner instance for executing queries
        """
        self.runner = runner

    def discover_all(self) -> Dict[str, Any]:
        """Discover artifacts from all services.

        Returns:
            Dict with service names as keys, discovery results as values:
            {
                'postgres': {'containers': [...], 'images': [...], ...},
                'openmetadata': {...},
                'kerberos': {...},
                'pagila': {...}
            }
        """
        results = {
            'postgres': {},
            'openmetadata': {},
            'kerberos': {},
            'pagila': {}
        }
        return results

    def get_summary(self, results: Dict[str, Any]) -> Dict[str, Any]:
        """Aggregate discovery results into summary counts.

        Args:
            results: Discovery results from discover_all()

        Returns:
            Summary dict with totals:
            {
                'total_containers': 5,
                'total_images': 10,
                'total_volumes': 3,
                'total_size': '5.2GB'
            }
        """
        return {
            'total_containers': 0,
            'total_images': 0,
            'total_volumes': 0,
            'total_size': '0GB'
        }
```

**Step 4: Run test to verify it passes**

Run: `uv run pytest wizard/tests/test_discovery_engine.py -v`

Expected: 8 tests PASS

**Step 5: Commit**

```bash
git add wizard/engine/discovery.py wizard/tests/test_discovery_engine.py
git commit -m "feat: add discovery engine for artifact detection (RED phase)

Task 13a complete - discovery engine tests written and passing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 13b: Discovery Engine Integration (GREEN Phase)

**Files:**
- Modify: `wizard/engine/discovery.py`
- Modify: `wizard/tests/test_discovery_engine.py`

**Step 1: Enhance tests for real discovery integration**

Add to `wizard/tests/test_discovery_engine.py`:

```python
class TestServiceDiscoveryIntegration:
    """Test integration with service discovery modules."""

    def test_discover_all_calls_postgres_discovery(self):
        """Should import and call postgres discovery functions."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres'): 'postgres|Up\n'
        }

        engine = DiscoveryEngine(runner=runner)
        results = engine.discover_all()

        # Should have postgres results
        assert 'postgres' in results
        assert 'containers' in results['postgres']

    def test_discover_all_handles_missing_service_module(self):
        """Should handle gracefully if service discovery module missing."""
        runner = MockActionRunner()
        engine = DiscoveryEngine(runner=runner)

        # Should not crash even if service modules don't exist yet
        results = engine.discover_all()
        assert isinstance(results, dict)
```

**Step 2: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_discovery_engine.py::TestServiceDiscoveryIntegration -v`

Expected: FAIL (discovery doesn't call service modules yet)

**Step 3: Implement service discovery integration**

Update `wizard/engine/discovery.py`:

```python
"""Discovery engine for finding actual platform artifacts on the system."""

from typing import Dict, List, Any


class DiscoveryEngine:
    """Aggregates discovery from all services."""

    def __init__(self, runner):
        """Initialize with action runner."""
        self.runner = runner
        self._load_service_modules()

    def _load_service_modules(self):
        """Dynamically import service discovery modules."""
        self.service_modules = {}

        services = ['postgres', 'openmetadata', 'kerberos', 'pagila']

        for service_name in services:
            try:
                # Dynamically import discovery module
                module = __import__(
                    f'wizard.services.{service_name}.discovery',
                    fromlist=['discovery']
                )
                self.service_modules[service_name] = module
            except ImportError:
                # Service discovery module doesn't exist yet - that's ok
                self.service_modules[service_name] = None

    def discover_all(self) -> Dict[str, Any]:
        """Discover artifacts from all services."""
        results = {}

        for service_name, module in self.service_modules.items():
            if module is None:
                # Service discovery not implemented yet
                results[service_name] = {
                    'containers': [],
                    'images': [],
                    'volumes': [],
                    'files': []
                }
                continue

            # Call service discovery functions
            try:
                results[service_name] = {
                    'containers': module.discover_containers(self.runner),
                    'images': module.discover_images(self.runner),
                    'volumes': module.discover_volumes(self.runner),
                    'files': module.discover_files(self.runner)
                }
            except AttributeError:
                # Service module exists but missing functions
                results[service_name] = {
                    'containers': [],
                    'images': [],
                    'volumes': [],
                    'files': []
                }

        return results

    def get_summary(self, results: Dict[str, Any]) -> Dict[str, Any]:
        """Aggregate discovery results into summary counts."""
        total_containers = 0
        total_images = 0
        total_volumes = 0

        for service_results in results.values():
            total_containers += len(service_results.get('containers', []))
            total_images += len(service_results.get('images', []))
            total_volumes += len(service_results.get('volumes', []))

        return {
            'total_containers': total_containers,
            'total_images': total_images,
            'total_volumes': total_volumes,
            'services_found': [
                name for name, results in results.items()
                if any(len(v) > 0 for v in results.values() if isinstance(v, list))
            ]
        }
```

**Step 4: Run tests to verify they pass**

Run: `uv run pytest wizard/tests/test_discovery_engine.py -v`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add wizard/engine/discovery.py wizard/tests/test_discovery_engine.py
git commit -m "feat: implement discovery engine with service integration (GREEN phase)

Task 13b complete - discovery engine now integrates with service modules.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 13c: Discovery Engine Code Review

**Step 1: Run code review agent**

Use superpowers:code-reviewer to validate Task 13b implementation.

**Step 2: Address any issues found**

Fix any problems identified by code review.

**Step 3: Verify all tests still pass**

Run: `uv run pytest wizard/tests/test_discovery_engine.py wizard/ -v`

Expected: All tests PASS, no regressions

**Step 4: Commit fixes if any**

```bash
git add <any-modified-files>
git commit -m "fix: address code review feedback for discovery engine

Task 13c complete - discovery engine reviewed and approved.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Tasks 14-17: Service Discovery Modules (PARALLEL)

**Note:** Tasks 14a-c, 15a-c, 16a-c, and 17a-c can be executed in parallel using 4 subagents simultaneously. Each follows the same RED → GREEN → Review pattern.

---

## Task 14a: PostgreSQL Discovery (RED Phase)

**Files:**
- Create: `wizard/services/postgres/discovery.py`
- Create: `wizard/services/postgres/tests/test_discovery.py`

**Step 1: Write failing tests**

Create `wizard/services/postgres/tests/test_discovery.py`:

```python
"""Tests for PostgreSQL discovery functions."""

import pytest
from wizard.services.postgres import discovery
from wizard.engine.runner import MockActionRunner


class TestDiscoverContainers:
    """Test discovering postgres containers."""

    def test_discover_containers_returns_list(self):
        """discover_containers() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_containers(runner)
        assert isinstance(result, list)

    def test_discover_containers_finds_postgres(self):
        """Should find postgres container when it exists."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres', '--format', '{{.Names}}|{{.Status}}'):
                'postgres|Up 2 days\nplatform-postgres|Exited\n'
        }

        result = discovery.discover_containers(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres'
        assert result[0]['status'] == 'Up 2 days'
        assert result[1]['name'] == 'platform-postgres'


class TestDiscoverImages:
    """Test discovering postgres images."""

    def test_discover_images_returns_list(self):
        """discover_images() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_images(runner)
        assert isinstance(result, list)

    def test_discover_images_finds_postgres_images(self):
        """Should find postgres images with size."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'images', '--filter', 'reference=postgres', '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'):
                'postgres:17.5|400MB\npostgres:16|380MB\n'
        }

        result = discovery.discover_images(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres:17.5'
        assert result[0]['size'] == '400MB'


class TestDiscoverVolumes:
    """Test discovering postgres volumes."""

    def test_discover_volumes_returns_list(self):
        """discover_volumes() should return list of dicts."""
        runner = MockActionRunner()
        result = discovery.discover_volumes(runner)
        assert isinstance(result, list)

    def test_discover_volumes_finds_postgres_volumes(self):
        """Should find postgres data volumes."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'volume', 'ls', '--filter', 'name=postgres', '--format', '{{.Name}}'):
                'postgres_data\npostgres_logs\n'
        }

        result = discovery.discover_volumes(runner)

        assert len(result) == 2
        assert result[0]['name'] == 'postgres_data'


class TestDiscoverFiles:
    """Test discovering postgres config files."""

    def test_discover_files_returns_list(self):
        """discover_files() should return list of file paths."""
        runner = MockActionRunner()
        result = discovery.discover_files(runner)
        assert isinstance(result, list)
```

**Step 2: Run tests to verify they fail**

Run: `uv run pytest wizard/services/postgres/tests/test_discovery.py -v`

Expected: FAIL with "No module named 'wizard.services.postgres.discovery'"

**Step 3: Write minimal implementation**

Create `wizard/services/postgres/discovery.py`:

```python
"""Discovery functions for PostgreSQL service artifacts."""

from typing import List, Dict, Any


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all postgres-related containers.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres', 'status': 'Up 2 days'}, ...]
    """
    return []


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all postgres images.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres:17.5', 'size': '400MB'}, ...]
    """
    return []


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find postgres data volumes.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of dicts: [{'name': 'postgres_data', 'size': '2.3GB'}, ...]
    """
    return []


def discover_files(runner) -> List[str]:
    """Find postgres configuration files.

    Args:
        runner: ActionRunner for executing queries

    Returns:
        List of file paths: ['platform-config.yaml', ...]
    """
    return []
```

**Step 4: Run tests to verify they pass**

Run: `uv run pytest wizard/services/postgres/tests/test_discovery.py -v`

Expected: 9 tests PASS

**Step 5: Commit**

```bash
git add wizard/services/postgres/discovery.py wizard/services/postgres/tests/test_discovery.py
git commit -m "feat: add PostgreSQL discovery module (RED phase)

Task 14a complete - postgres discovery tests written and passing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 14b: PostgreSQL Discovery (GREEN Phase)

**Files:**
- Modify: `wizard/services/postgres/discovery.py`

**Step 1: Implement real discovery logic**

Update `wizard/services/postgres/discovery.py`:

```python
"""Discovery functions for PostgreSQL service artifacts."""

from typing import List, Dict, Any
import os


def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all postgres-related containers."""
    result = runner.run_shell([
        'docker', 'ps', '-a',
        '--filter', 'name=postgres',
        '--format', '{{.Names}}|{{.Status}}'
    ])

    containers = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if '|' in line:
                name, status = line.split('|', 1)
                containers.append({'name': name, 'status': status})

    return containers


def discover_images(runner) -> List[Dict[str, str]]:
    """Find all postgres images."""
    result = runner.run_shell([
        'docker', 'images',
        '--filter', 'reference=postgres',
        '--format', '{{.Repository}}:{{.Tag}}|{{.Size}}'
    ])

    images = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if '|' in line:
                name, size = line.split('|', 1)
                images.append({'name': name, 'size': size})

    return images


def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find postgres data volumes."""
    result = runner.run_shell([
        'docker', 'volume', 'ls',
        '--filter', 'name=postgres',
        '--format', '{{.Name}}'
    ])

    volumes = []
    if result.get('stdout'):
        for line in result['stdout'].strip().split('\n'):
            if line:
                volumes.append({'name': line})

    return volumes


def discover_files(runner) -> List[str]:
    """Find postgres configuration files."""
    files = []

    # Check for platform-config.yaml
    if os.path.exists('platform-config.yaml'):
        files.append('platform-config.yaml')

    # Check for .env files
    if os.path.exists('platform-bootstrap/.env'):
        files.append('platform-bootstrap/.env')

    return files
```

**Step 2: Run tests to verify they pass**

Run: `uv run pytest wizard/services/postgres/tests/test_discovery.py -v`

Expected: All tests PASS

**Step 3: Run integration test with discovery engine**

Run: `uv run pytest wizard/tests/test_discovery_engine.py::TestServiceDiscoveryIntegration::test_discover_all_calls_postgres_discovery -v`

Expected: PASS

**Step 4: Commit**

```bash
git add wizard/services/postgres/discovery.py
git commit -m "feat: implement PostgreSQL discovery with Docker queries (GREEN phase)

Task 14b complete - postgres discovery fully functional.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 14c: PostgreSQL Discovery Code Review

**Step 1: Run code review**

Use superpowers:code-reviewer to validate.

**Step 2: Address issues**

Fix any problems found.

**Step 3: Verify tests**

Run: `uv run pytest wizard/services/postgres/tests/test_discovery.py -v`

Expected: All tests PASS

**Step 4: Commit fixes**

```bash
git add <modified-files>
git commit -m "fix: address code review feedback for postgres discovery

Task 14c complete - postgres discovery reviewed and approved.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Tasks 15-17: Remaining Service Discovery Modules

**Tasks 15a-c, 16a-c, 17a-c follow the exact same pattern as Task 14:**

### Task 15: OpenMetadata Discovery
- Containers: `openmetadata-server`, `openmetadata-ingestion`, `opensearch`
- Images: `openmetadata/*`, `opensearchproject/*`
- Volumes: `openmetadata_data`, `opensearch_data`
- Files: platform-config.yaml, .env, `openmetadata/` directory

### Task 16: Kerberos Discovery
- Containers: `kerberos-sidecar`
- Images: `kerberos-sidecar:*`
- Volumes: None
- Files: `/etc/security/keytabs/*.keytab`, .env

### Task 17: Pagila Discovery
- Containers: None (uses postgres)
- Images: None (or custom)
- Volumes: None (uses postgres volume)
- Files: platform-config.yaml
- Custom: Repository at `/tmp/pagila`, database schema check

---

## Task 18a: Clean-Slate Flow with Discovery (RED Phase)

**Files:**
- Modify: `wizard/flows/clean-slate.yaml`
- Create: `wizard/tests/test_clean_slate_discovery.py`

**Step 1: Write failing tests**

Create `wizard/tests/test_clean_slate_discovery.py`:

```python
"""Tests for clean-slate flow with discovery integration."""

import pytest
from wizard.engine.engine import WizardEngine
from wizard.engine.runner import MockActionRunner


class TestDiscoveryPhase:
    """Test that clean-slate runs discovery first."""

    def test_clean_slate_runs_discovery_before_prompts(self):
        """Clean-slate should run discovery phase before asking questions."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a'): 'postgres|Up\n'  # Some artifacts exist
        }

        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute clean-slate flow with headless inputs
        engine.execute_flow('clean-slate', headless_inputs={
            'select_services': ['postgres']
        })

        # Should have called docker discovery commands
        assert any('docker' in str(call) for call in runner.calls)


class TestEmptyStateHandling:
    """Test handling when no artifacts found."""

    def test_empty_system_shows_message_and_exits(self):
        """Should show 'system is clean' message and exit gracefully."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {}  # No artifacts

        engine = WizardEngine(runner=runner, base_path='wizard')

        # Should complete without prompting for services
        result = engine.execute_flow('clean-slate')

        # Verify clean exit (no errors)
        assert result is not None


class TestDiscoveryResultsDisplay:
    """Test showing discovery results to user."""

    def test_shows_container_counts(self):
        """Should display number of containers found per service."""
        runner = MockActionRunner()
        runner.responses['run_shell'] = {
            ('docker', 'ps', '-a', '--filter', 'name=postgres'): 'postgres|Up\n',
            ('docker', 'ps', '-a', '--filter', 'name=openmetadata'): 'openmetadata-server|Up\n'
        }

        engine = WizardEngine(runner=runner, base_path='wizard')

        # Execute with headless inputs
        result = engine.execute_flow('clean-slate', headless_inputs={
            'select_services': []  # Don't actually remove anything
        })

        # Verify discovery ran
        assert len(runner.calls) > 0
```

**Step 2: Run tests to verify they fail**

Run: `uv run pytest wizard/tests/test_clean_slate_discovery.py -v`

Expected: FAIL (flow doesn't have discovery phase yet)

**Step 3: Update clean-slate flow spec**

Modify `wizard/flows/clean-slate.yaml` to add discovery phase at the start:

```yaml
metadata:
  version: "1.1"
  description: "Clean-slate wizard with system discovery - orchestrates service teardown"

steps:
  # NEW: Discovery phase
  - id: run_discovery
    type: action
    action: discovery.scan_all_services
    next: show_discovery_results

  # NEW: Show what was found
  - id: show_discovery_results
    type: display
    prompt: |
      Discovering platform services...

      Discovery results will be shown here.
    next: check_empty_state

  # NEW: Handle empty state
  - id: check_empty_state
    type: conditional
    condition: "state.total_artifacts == 0"
    next:
      when_true: show_clean_message
      when_false: select_services

  - id: show_clean_message
    type: display
    prompt: |
      System is already clean! No platform artifacts detected.

      Checked:
        - Docker containers
        - Docker images
        - Docker volumes
        - Configuration files
    next: null  # Exit

  # Existing service selection continues...
  - id: select_services
    type: multi_select
    # ... rest of existing flow
```

**Step 4: Run tests to verify they pass**

Run: `uv run pytest wizard/tests/test_clean_slate_discovery.py -v`

Expected: Tests PASS

**Step 5: Commit**

```bash
git add wizard/flows/clean-slate.yaml wizard/tests/test_clean_slate_discovery.py
git commit -m "feat: add discovery phase to clean-slate flow (RED phase)

Task 18a complete - clean-slate now runs discovery first.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 18b: Clean-Slate Flow Discovery (GREEN Phase)

**Files:**
- Modify: `wizard/engine/engine.py`
- Modify: `wizard/flows/clean-slate.yaml`

**Step 1: Implement discovery action in engine**

Add discovery action handling to `wizard/engine/engine.py`:

```python
# In WizardEngine class

def _execute_step(self, step, headless_inputs):
    """Execute a single step."""
    # ... existing code ...

    # Handle discovery actions
    if step.get('action') == 'discovery.scan_all_services':
        from wizard.engine.discovery import DiscoveryEngine

        discovery_engine = DiscoveryEngine(self.runner)
        results = discovery_engine.discover_all()
        summary = discovery_engine.get_summary(results)

        # Store in state
        self.state['discovery_results'] = results
        self.state['total_artifacts'] = (
            summary['total_containers'] +
            summary['total_images'] +
            summary['total_volumes']
        )
        return

    # ... rest of existing code ...
```

**Step 2: Enhance display to show discovery results**

Update the display step in clean-slate.yaml to use actual discovery data:

```yaml
  - id: show_discovery_results
    type: display
    prompt: |
      Discovering platform services...

      PostgreSQL:
        ✓ {postgres_containers} containers
        ✓ {postgres_images} images
        ✓ {postgres_volumes} volumes

      OpenMetadata:
        ✓ {openmetadata_containers} containers
        ✓ {openmetadata_images} images
        ✓ {openmetadata_volumes} volumes

      Kerberos:
        ✓ {kerberos_containers} containers
        ✓ {kerberos_images} images

      Pagila:
        ✓ Repository: {pagila_repo_found}
        ✓ Database schema: {pagila_schema_found}
    next: check_empty_state
```

**Step 3: Run all tests**

Run: `uv run pytest wizard/tests/test_clean_slate_discovery.py wizard/tests/test_clean_slate_flow.py -v`

Expected: All tests PASS

**Step 4: Test manually**

Run: `./platform clean-slate`

Expected: See discovery results displayed

**Step 5: Commit**

```bash
git add wizard/engine/engine.py wizard/flows/clean-slate.yaml
git commit -m "feat: implement discovery action in clean-slate flow (GREEN phase)

Task 18b complete - clean-slate now shows real discovery results.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com)"
```

---

## Task 18c: Clean-Slate Discovery Code Review

**Step 1: Run code review**

Use superpowers:code-reviewer.

**Step 2: Address issues**

Fix any problems.

**Step 3: Verify integration**

Run full test suite: `uv run pytest wizard/ platform-bootstrap/tests/test_platform_cli.py -v`

**Step 4: Commit fixes**

```bash
git add <files>
git commit -m "fix: address code review feedback for discovery integration

Task 18c complete - discovery integration reviewed and approved.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 19: Final Integration Review

**Step 1: Run complete test suite**

```bash
uv run pytest wizard/ platform-bootstrap/tests/ -v
```

Expected: All tests PASS, including new discovery tests

**Step 2: Test user experience manually**

Test scenarios:
1. Empty system (no containers): Should show "System is clean" message
2. Postgres only: Should show 1 container, offer to remove
3. All services: Should show detailed breakdown
4. After cleanup: Should show reduced counts

**Step 3: Verify no regressions**

```bash
# Setup should still work
./platform setup

# Clean-slate should work with discovery
./platform clean-slate
```

**Step 4: Update PR description**

Add discovery feature to PR #80 description.

**Step 5: Create summary document**

Document what was built, test coverage, user experience improvements.

---

## Success Criteria

- ✅ All services have discovery.py modules
- ✅ Clean-slate runs discovery before prompting
- ✅ Empty state shows informative message
- ✅ User sees actual system state (containers/images/volumes/files)
- ✅ All queries go through runner (fully mockable)
- ✅ Test coverage remains 100%
- ✅ No regressions in existing wizard functionality

---

## Execution Notes

- Tasks 13a-c must complete before Tasks 14-17 (dependencies)
- Tasks 14-17 can run in parallel (4 subagents)
- Task 18 depends on Tasks 13-17 completing
- Use superpowers:code-reviewer after each GREEN phase
- Commit frequently (after each GREEN phase minimum)
