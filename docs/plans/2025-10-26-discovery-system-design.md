# Discovery System Design for Clean-Slate Wizard

**Date:** 2025-10-26
**Status:** Approved for Implementation

## Problem Statement

The current clean-slate wizard only reads `platform-config.yaml` to determine what to clean up. It doesn't check actual system state, leading to:

1. **Orphaned artifacts** - Containers/images/volumes remain if config is deleted
2. **Poor user feedback** - User doesn't know what actually exists
3. **No validation** - Setup can't verify what was actually created
4. **Silent failures** - Wizard exits silently when nothing in config, even if Docker artifacts exist

**Example of current problem:**
```bash
$ ./platform clean-slate
✓ Clean-slate complete!  # But postgres containers still running!
```

## Solution Overview

Add a **discovery system** where each service module defines how to query actual system state. Discovery functions work for both:
- **Setup validation** - Verify artifacts were created correctly
- **Teardown discovery** - Find what actually exists to clean up

## Design Principles

1. **Query actual state** - Always check Docker/filesystem, not just config
2. **Granular control** - User chooses what to remove at each layer (containers, images, volumes, files)
3. **Always fresh** - No caching, query state before each decision
4. **Service manifests** - Each service defines what it physically consists of
5. **Mockable** - All queries go through runner interface (fully testable)

## Architecture

### File Structure

```
wizard/services/{service}/
├── spec.yaml              # Setup flow (existing)
├── teardown-spec.yaml     # Teardown flow (existing)
├── validators.py          # Pure validators (existing)
├── actions.py             # Setup actions (existing)
├── teardown_actions.py    # Teardown actions (existing)
├── discovery.py           # NEW - Discovery functions
└── tests/
    ├── test_discovery.py  # NEW - Discovery tests
    └── ...
```

### Discovery Module Interface

Each service implements standard discovery functions:

```python
# wizard/services/postgres/discovery.py

def discover_containers(runner) -> List[Dict[str, str]]:
    """Find all postgres-related containers (running or stopped).

    Returns: [
        {'name': 'postgres', 'status': 'Up 2 days'},
        {'name': 'platform-postgres', 'status': 'Exited'},
        ...
    ]
    """
    result = runner.run_shell([
        'docker', 'ps', '-a',
        '--filter', 'name=postgres',
        '--format', '{{.Names}}|{{.Status}}'
    ])
    # Parse output into list of dicts

def discover_images(runner) -> List[Dict[str, str]]:
    """Find all postgres images.

    Returns: [
        {'name': 'postgres:17.5', 'size': '400MB'},
        {'name': 'postgres:16', 'size': '380MB'},
        ...
    ]
    """

def discover_volumes(runner) -> List[Dict[str, str]]:
    """Find postgres data volumes.

    Returns: [
        {'name': 'postgres_data', 'size': '2.3GB'},
        {'name': 'postgres_logs', 'size': '100MB'},
        ...
    ]
    """

def discover_files(runner) -> List[str]:
    """Find postgres configuration files.

    Returns: [
        'platform-config.yaml',
        'platform-bootstrap/.env',
        ...
    ]
    """

def get_summary(runner) -> Dict[str, Any]:
    """Aggregate discovery results for display.

    Returns: {
        'containers': 1,
        'images': 2,
        'volumes': 1,
        'total_size': '2.7GB'
    }
    """
```

### Service-Specific Artifacts

Each service has different physical components:

| Service | Containers | Images | Volumes | Files | Custom |
|---------|-----------|--------|---------|-------|--------|
| **PostgreSQL** | postgres, platform-postgres | postgres:* | postgres_data, postgres_logs | .env, config | - |
| **OpenMetadata** | openmetadata-server, openmetadata-ingestion, opensearch | openmetadata/*, opensearchproject/* | openmetadata_data, opensearch_data | .env, config, openmetadata/ dir | - |
| **Kerberos** | kerberos-sidecar | kerberos-sidecar:* | - | /etc/security/keytabs/*.keytab, .env | - |
| **Pagila** | - | (optional custom) | - | config | Git repo (/tmp/pagila), Database schema |

### Clean-Slate Flow Integration

Update `wizard/flows/clean-slate.yaml`:

```yaml
steps:
  # NEW: Discovery phase
  - id: discovery_phase
    type: action
    action: discovery.scan_all_services
    next: show_discovery_results

  # NEW: Show what was found
  - id: show_discovery_results
    type: display
    prompt: |
      Discovering platform services...

      PostgreSQL:
        ✓ {postgres_containers} containers
        ✓ {postgres_images} images ({postgres_size})
        ✓ {postgres_volumes} volumes

      OpenMetadata:
        ✓ {openmetadata_containers} containers
        ✓ {openmetadata_images} images
        ...
    next: check_empty_state

  # NEW: Handle empty state
  - id: check_empty_state
    type: conditional
    condition: total_artifacts == 0
    next:
      when_true: show_clean_message
      when_false: select_services

  - id: show_clean_message
    type: display
    prompt: |
      System is already clean! No platform artifacts detected.

      Checked:
        - Docker containers (postgres, openmetadata, kerberos, pagila)
        - Docker images (matching service patterns)
        - Docker volumes (service data)
        - Configuration files (platform-config.yaml, .env files)
    next: exit

  # Existing flow continues...
  - id: select_services
    type: multi_select
    # ...
```

### Enhanced Teardown Experience

**Before (current):**
```
Clean-Slate Wizard
✓ Clean-slate complete!
```

**After (with discovery):**
```
════════════════════════════════════════════════════════
  Clean-Slate Wizard
════════════════════════════════════════════════════════

Discovering platform services...

PostgreSQL:
  ✓ 1 container found (postgres - Up 2 days)
  ✓ 2 images found (postgres:17.5, postgres:16 - 780MB total)
  ✓ 1 volume found (postgres_data - 2.3GB)
  ✓ Config found

OpenMetadata:
  ✓ 3 containers found
  ✓ 4 images found (1.2GB total)
  ✓ 2 volumes found (800MB)

Kerberos:
  ⚠ No artifacts found

Pagila:
  ✓ Repository found (/tmp/pagila - 15MB)
  ✓ Database schema found

────────────────────────────────────────────────────────

Select services to remove [postgres,openmetadata,pagila]: postgres

────────────────────────────────────────────────────────
PostgreSQL Cleanup
────────────────────────────────────────────────────────

Remove containers? (postgres) [y/N]: y
Remove images? (postgres:17.5, postgres:16 - 780MB) [y/N]: n
Remove volumes? (postgres_data - 2.3GB) [y/N]: n
Remove config entries? [y/N]: n

✓ Stopped and removed 1 container
✓ Kept 2 images (780MB preserved)
✓ Kept 1 volume (2.3GB preserved)
✓ Kept configuration

════════════════════════════════════════════════════════
[OK] Clean-slate complete!

Summary:
  - Removed: 1 container
  - Preserved: 2 images (780MB), 1 volume (2.3GB)
  - Freed: minimal disk space
════════════════════════════════════════════════════════
```

## Testing Strategy

### Test Layers

**1. Unit Tests (discovery.py functions)**
- Parse docker command output correctly
- Handle empty results gracefully
- Format sizes/counts for display
- Service-specific queries are correct

**2. Integration Tests (with MockActionRunner)**
- Discovery functions call correct docker commands
- Empty state detection works
- Aggregation across services works
- Flow integration works

### Test Scenarios

1. **All services present** - Discovery finds everything
2. **Partial cleanup** - Some services removed, others remain
3. **Empty system** - Nothing found, shows clean message
4. **Mixed state** - Containers exist but images removed
5. **Pagila edge cases** - Repo exists but database doesn't, or vice versa

### Mock Responses

```python
# Test with MockActionRunner
mock_runner = MockActionRunner()
mock_runner.responses['run_shell'] = {
    ('docker', 'ps', '-a', '--filter', 'name=postgres'): "postgres|Up 2 days\n",
    ('docker', 'images', '--filter', 'reference=postgres'): "postgres:17.5|400MB\n",
    ('docker', 'volume', 'ls', '--filter', 'name=postgres'): "postgres_data\n",
}

# Test discovery
from wizard.services.postgres import discovery
containers = discovery.discover_containers(mock_runner)
assert len(containers) == 1
assert containers[0]['name'] == 'postgres'
```

## Implementation Plan

### Task Breakdown (Parallel + Serial Pattern)

**Phase 1: Serial (Core Discovery Infrastructure)**
- Task 13a-c: Discovery engine integration (RED/GREEN/Review)

**Phase 2: Parallel (Service Discovery Modules)**
- Task 14a-c: PostgreSQL discovery (RED/GREEN/Review)
- Task 15a-c: OpenMetadata discovery (RED/GREEN/Review)
- Task 16a-c: Kerberos discovery (RED/GREEN/Review)
- Task 17a-c: Pagila discovery (RED/GREEN/Review)

**Phase 3: Serial (Flow Integration)**
- Task 18a-c: Clean-slate flow with discovery (RED/GREEN/Review)
- Task 19: Final integration review

### Parallel Execution Strategy

Tasks 14-17 can run in parallel because:
- Each service discovery module is independent
- No shared state between services
- Same interface pattern (discover_containers, discover_images, etc.)
- Enables 4x speedup during development

### Success Criteria

- Discovery finds actual system state (not just config)
- Empty state shows informative message
- User has granular control (containers, images, volumes, files)
- All queries go through runner (fully mockable)
- Test coverage remains at 100%
- Fast execution (discovery queries add <2 seconds)

## Future Enhancements (Out of Scope)

1. **Setup validation** - Use discovery to verify artifacts after setup
2. **Health checks** - Extend discovery to check if services are healthy
3. **Disk space analysis** - Show potential space savings before cleanup
4. **Export/import state** - Save discovery results for later comparison
5. **Convention-based scanning** - Auto-detect platform-* containers even if not in manifest

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Docker queries slow | Cache results within single wizard session if needed |
| Partial docker permissions | Graceful degradation, show what we can detect |
| Complex parsing logic | Extensive unit tests for all output formats |
| Service-specific edge cases | Comprehensive test scenarios per service |

## Backward Compatibility

- No breaking changes to existing wizard
- Discovery is additive (doesn't remove existing functionality)
- Tests still pass with MockActionRunner
- User workflow unchanged (just better feedback)

## Appendix: Docker Query Examples

### Container Discovery
```bash
docker ps -a --filter "name=postgres" --format "{{.Names}}|{{.Status}}|{{.CreatedAt}}"
# Output: postgres|Up 2 days|2025-10-24 10:30:00
```

### Image Discovery
```bash
docker images --filter "reference=postgres" --format "{{.Repository}}:{{.Tag}}|{{.Size}}"
# Output: postgres:17.5|400MB
```

### Volume Discovery
```bash
docker volume ls --filter "name=postgres" --format "{{.Name}}"
docker volume inspect postgres_data --format "{{.Mountpoint}}|{{.Options.size}}"
# Output: postgres_data
#         /var/lib/docker/volumes/postgres_data|2.3GB
```

### Size Calculation
```bash
docker system df -v --format "{{.Type}}|{{.TotalCount}}|{{.Size}}"
# Output: Containers|10|2.5GB
#         Images|20|15GB
#         Volumes|5|3GB
```

---

**Design Status:** Ready for Implementation
**Next Steps:** Phase 5 (Worktree Setup) → Phase 6 (Implementation Plan)
