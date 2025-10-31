# Git Cleanup Audit

A production-ready git cleanup utility designed for agent and automation use with minimal token consumption.

## Overview

`git-cleanup-audit.py` is an agent-optimized tool that safely cleans up local git branches and worktrees after PRs are merged. It operates with an auditor's mindset, ensuring all local work is accounted for in main before any deletion occurs.

## Key Features

- **Agent-Optimized**: Outputs only "OK" on success (1 token!) for minimal LLM token usage
- **Safe by Design**: Comprehensive pre-flight checks prevent data loss
- **Parallel Processing**: Uses multiprocessing for fast verification
- **Comprehensive Error Handling**: Graceful degradation with detailed error reporting
- **Worktree Support**: Handles both branches and git worktrees correctly

## Installation

The utility is located at the repository root:

```bash
./git-cleanup-audit.py
```

Make sure it's executable:
```bash
chmod +x git-cleanup-audit.py
```

## Usage

### Basic Usage

```bash
# From main branch, clean all merged branches and worktrees
./git-cleanup-audit.py
```

**Output on success:** `OK`

### Options

```bash
./git-cleanup-audit.py [options]
```

Options:
- `--dry-run` - Audit only, don't delete anything
- `--verbose` - Show detailed output
- `--workers N` - Number of parallel workers (default: CPU count)
- `--skip-fetch` - Skip fetching from origin (for offline use)

### Examples

**See what would be cleaned:**
```bash
./git-cleanup-audit.py --dry-run --verbose
```

Output:
```
worktree: /path/to/worktree
branch: feature/old-branch
2 entities
```

**Run cleanup with verbose feedback:**
```bash
./git-cleanup-audit.py --verbose
```

**Offline mode (skip fetch):**
```bash
./git-cleanup-audit.py --skip-fetch
```

## Exit Codes

- `0`: Success - all branches/worktrees cleaned or nothing to clean
- `1`: Unmerged work detected - review required before cleanup
- `2`: Pre-flight check failed - manual intervention required
  - Not on main branch
  - Uncommitted changes detected
  - Stashes detected
  - Not a git repository
- `3`: Execution error - git command failed or cleanup failed

## Safety Mechanisms

### Pre-flight Checks

The tool will refuse to run if:
1. Not in a git repository
2. Not on the main branch
3. Uncommitted changes exist
4. Stashes exist

### Verification Before Deletion

For each branch/worktree:
1. Fetches latest from origin (unless `--skip-fetch`)
2. Verifies all commits exist in main using `git rev-list`
3. Only deletes if fully merged

### Conservative Approach

If any check fails, the tool assumes unsafe and either:
- Exits with code 2 (pre-flight failure)
- Reports the entity as having unmerged work
- Reports execution error with details

## Agent Integration

The tool is designed for use by LLM agents and automation:

### Python Integration

```python
import subprocess

result = subprocess.run(["./git-cleanup-audit.py"], capture_output=True, text=True)

if result.returncode == 0:
    # Safe to proceed - everything clean
    print("Repository cleaned")
elif result.returncode == 1:
    # Unmerged work detected
    print(f"Review required: {result.stdout}")
elif result.returncode == 2:
    # Pre-flight failed
    print(f"Manual intervention: {result.stdout}")
else:
    # Execution error
    print(f"Error: {result.stdout}")
```

### MCP Server Integration

The tool can be exposed through an MCP server for agent use:

```python
# Example MCP tool definition
{
    "name": "git_cleanup_audit",
    "description": "Clean up merged git branches and worktrees",
    "inputSchema": {
        "type": "object",
        "properties": {
            "dry_run": {"type": "boolean"},
            "verbose": {"type": "boolean"}
        }
    }
}
```

## Performance

- **Small repos** (<3 entities): Processes serially (avoids pool overhead)
- **Large repos** (3+ entities): Uses parallel processing with multiprocessing.Pool
- **Typical cleanup** (10 branches): ~0.5-1 second with parallel processing

## Architecture

### Design Principles

1. **Minimal Token Usage**: Single word output on success
2. **No Files Written**: Happy path writes no files (zero I/O overhead)
3. **Conservative Safety**: Fail safe on any uncertainty
4. **Clear Error Messages**: Detailed errors only when needed

### Implementation Details

- **Language**: Python 3.8+
- **Dependencies**: Standard library only (subprocess, multiprocessing, argparse)
- **Parallel Strategy**: Scatter/gather with process pool
- **Error Handling**: All git commands wrapped with error checking

## Development

### Running Tests

```bash
cd .worktrees/git-cleanup-audit  # or wherever the dev version is
python3 -m pytest tests/test_git_cleanup_audit.py -v
```

All 7 tests should pass:
- ✓ Minimal output on success
- ✓ Uncommitted changes detection
- ✓ Stash detection
- ✓ Branch discovery
- ✓ Unmerged work detection
- ✓ Merged branch cleanup
- ✓ Worktree cleanup

### Design Documentation

See `docs/plans/2025-10-31-git-cleanup-audit-design.md` for detailed design rationale and architecture decisions.

## Common Use Cases

### After PR Merge

```bash
# User just merged PR #123 via GitHub
git checkout main
git pull
./git-cleanup-audit.py

# Output: OK
# All merged branches and worktrees cleaned up
```

### Before Context Switch

```bash
# Clean up before switching to new work
./git-cleanup-audit.py --verbose

# Shows what gets cleaned
# Ensures no forgotten work
```

### CI/CD Integration

```bash
# In CI pipeline after merge
git checkout main
git pull
./git-cleanup-audit.py || {
    case $? in
        1) echo "Unmerged work - skipping cleanup" ;;
        2) echo "Pre-flight failed - check repo state" ;;
        3) echo "Execution error - check logs" ;;
    esac
}
```

## Troubleshooting

### "Error: Must be on main branch"

Solution: Checkout main first
```bash
git checkout main
./git-cleanup-audit.py
```

### "Uncommitted changes detected"

Solution: Commit or stash your changes
```bash
git add .
git commit -m "Your changes"
# or
git stash
```

Then run the cleanup.

### "Branch X: N commit(s) not in main"

This is expected behavior - the branch has unmerged work. Options:
1. Review the branch: `git log main..branch-name`
2. Merge it: Create a PR or merge locally
3. Delete manually if the work isn't needed: `git branch -D branch-name`

### "Failed to clean worktree X: error message"

This usually means:
- Worktree has uncommitted changes
- Permission issues
- Worktree is locked by another process

Solution: Navigate to the worktree and check its state, or remove manually.

## Credits

Designed and implemented following Test-Driven Development (TDD) methodology with comprehensive error handling and safety checks.

Built for the Airflow Data Platform project to support efficient git workflow automation.

## License

Part of the Airflow Data Platform project.