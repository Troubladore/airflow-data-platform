#!/usr/bin/env python3
"""Test that git-cleanup-audit handles worktrees and branches in correct order"""

import subprocess
import tempfile
import os
import shutil
from pathlib import Path


def run_command(cmd, cwd=None):
    """Run a command and return (success, stdout, stderr)"""
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=cwd,
        shell=isinstance(cmd, str)
    )
    return result.returncode == 0, result.stdout, result.stderr


def test_two_phase_cleanup():
    """Test that worktrees are processed before branches"""

    # Create a temporary git repository for testing
    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize repo
        success, _, _ = run_command(["git", "init"], cwd=repo_path)
        assert success, "Failed to init repo"

        # Configure git
        run_command(["git", "config", "user.email", "test@example.com"], cwd=repo_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=repo_path)

        # Create initial commit on main
        test_file = repo_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=repo_path)

        # Create a feature branch with a commit
        run_command(["git", "checkout", "-b", "feature/test-branch"], cwd=repo_path)
        test_file.write_text("feature change")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Feature commit"], cwd=repo_path)

        # Merge back to main (so branch is fully merged)
        run_command(["git", "checkout", "main"], cwd=repo_path)
        run_command(["git", "merge", "feature/test-branch"], cwd=repo_path)

        # Copy the cleanup script to the test repo BEFORE creating worktree
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script = repo_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script)
        test_script.chmod(0o755)

        # Add gitignore for worktrees (like a real repo would have)
        gitignore = repo_path / ".gitignore"
        gitignore.write_text(".worktrees/\n")

        # Commit the script and gitignore so we have a clean working directory
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Add cleanup script and gitignore"], cwd=repo_path)

        # NOW create a worktree using the feature branch (after gitignore is in place)
        worktree_path = repo_path / ".worktrees" / "test-worktree"
        success, _, stderr = run_command(
            ["git", "worktree", "add", str(worktree_path), "feature/test-branch"],
            cwd=repo_path
        )
        assert success, f"Failed to create worktree: {stderr}"

        # Run the cleanup utility in verbose mode to see what's happening
        success, stdout, stderr = run_command(
            ["python3", str(test_script), "--verbose"],
            cwd=repo_path
        )

        # The bug: utility should succeed but currently fails
        # because it tries to delete the branch before the worktree
        print(f"=== VERBOSE OUTPUT ===")
        print(f"stdout: {stdout}")
        print(f"stderr: {stderr}")
        print(f"success: {success}")

        # Check if the real issue is happening
        if "cannot delete branch" in stderr and "used by worktree" in stderr:
            print("✗ Found the bug: trying to delete branch used by worktree")

        assert success, f"Cleanup should succeed with two-phase processing"

        # Verify worktree is gone
        success, stdout, _ = run_command(["git", "worktree", "list"], cwd=repo_path)
        assert success
        assert str(worktree_path) not in stdout, "Worktree should be removed"

        # Verify branch is gone
        success, stdout, _ = run_command(["git", "branch"], cwd=repo_path)
        assert success
        assert "feature/test-branch" not in stdout, "Branch should be removed"

        # Verify main is still there
        assert "main" in stdout or "* main" in stdout, "Main branch should remain"

        print("✓ Two-phase cleanup test passed")


if __name__ == "__main__":
    test_two_phase_cleanup()