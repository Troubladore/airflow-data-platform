# Git Cleanup Audit Tool Design

## Overview
A Python multiprocessing tool that cleans up local git branches and worktrees after PR merges, operating with auditor-level rigor to ensure all local work is accounted for in main.

## Requirements
- Verify all local commits exist in main before cleanup
- Process branches and worktrees in parallel for efficiency
- Report unmerged work without cleaning it
- Generate both JSON and markdown reports
- Fail fast on any unsafe conditions

## Architecture

### Scatter/Gather Pattern
**Main Process**:
- Serial discovery of branches, worktrees, remotes
- Dispatch work units to process pool
- Gather worker results
- Compile final report

**Worker Processes** (parallel):
- Receive work unit: `(entity_type, entity_name, entity_path)`
- Discover commits in assigned entity
- Audit commits against origin/main
- Return success or failure details

### Work Unit Types
- `branch`: Local branch name and ref
- `worktree`: Worktree path and branch ref
- `remote_tracking`: Remote branch for pruning

## Data Flow

### Verification Logic
```python
def verify_entity(entity):
    local_commits = get_commits_not_in_main(entity)
    if local_commits:
        return {"status": "failed", "entity": entity, "unmerged": local_commits}
    return {"status": "clean", "entity": entity}
```

### Output Location
All outputs in `.git-cleanup-audit/` (gitignored):
- `audit-TIMESTAMP.json` - Full audit log
- `report-TIMESTAMP.md` - Human summary (only if failures)
- `checkpoint/` - Recovery checkpoints

### Cleanup Actions
- Branches: `git branch -D` only if fully merged
- Worktrees: `git worktree remove` only if no local commits
- Remotes: `git remote prune` for stale refs

## Safety & Error Handling

### Pre-flight Checks (blocking)
```python
def preflight_checks():
    assert not has_uncommitted_changes()
    assert not has_stashes()
    assert can_fetch_origin()
    assert on_main_branch()
    git_fetch_prune()  # Get latest remote state
```

### Worker Error Isolation
- Each worker wrapped in try/except
- Git failures logged with stderr
- Worker crashes isolated from others
- Failed entities collected for report

### Failure Handling
- Detached HEAD: Skip with warning
- Corrupt refs: Report and skip
- Permission errors: Report and skip
- Missing commits: Report as unmerged

## Command Line Interface

### Usage
```bash
git-cleanup-audit [options]
```

### Options
- `--dry-run`: Audit only, no deletions
- `--workers N`: Parallel workers (default: CPU count)
- `--resume`: Resume from checkpoint
- `--json-only`: JSON output only
- `--verbose`: Include git command outputs
- `--include-stashes`: Also audit stashes

### Exit Codes
- 0: Completed successfully
- 1: Unmerged work detected
- 2: Pre-flight checks failed (manual intervention required)
- 3: Worker failures during execution

### Philosophy
No force option - if checks fail, manual intervention required.

## Report Formats

### JSON Report
```json
{
  "timestamp": "2025-10-31T10:45:00Z",
  "status": "failed",
  "entities_scanned": 12,
  "entities_cleaned": 10,
  "failures": [
    {
      "type": "branch",
      "name": "feature/unmerged",
      "commits": ["a1b2c3d", "e4f5g6h"],
      "reason": "commits not in main"
    }
  ]
}
```

### Console Output
```
Scanning: 12 entities found
Processing: [████████████████████] 12/12
Branch feature/unmerged: commits a1b2c3d, e4f5g6h not in main
Cleaned: 10 entities
```

### Markdown (failures only)
```markdown
## Git Cleanup Audit - 2025-10-31 10:45:00

### Unmerged Work Detected
- **feature/unmerged**: 2 commits not in main
- **.worktrees/experiment**: 1 commit not in main
```

## Success Criteria
- All local work accounted for
- No data loss possible
- Clear audit trail
- Fast parallel execution
- Minimal output on success ("Completed successfully")