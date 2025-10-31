#!/usr/bin/env python3
"""TDD tests for git-cleanup-audit preflight checks

Tests the new preflight functionality that should happen BEFORE existing checks:
1. Switch to main branch if not already on it
2. Change to repository root if in subdirectory
3. Pull latest from origin/main
"""

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


def test_switch_to_main_branch():
    """Test that script switches to main branch if on different branch"""

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize repo
        run_command(["git", "init"], cwd=repo_path)
        run_command(["git", "config", "user.email", "test@example.com"], cwd=repo_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=repo_path)

        # Create initial commit on main
        test_file = repo_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=repo_path)

        # Copy the cleanup script to main branch first
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script = repo_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script)
        test_script.chmod(0o755)

        # Commit the script on main so we have a clean working directory
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Add cleanup script"], cwd=repo_path)

        # Create and switch to feature branch
        run_command(["git", "checkout", "-b", "feature/test"], cwd=repo_path)

        # Verify we're on feature branch
        success, stdout, _ = run_command(["git", "branch", "--show-current"], cwd=repo_path)
        assert success
        assert stdout.strip() == "feature/test", f"Should be on feature/test, got {stdout.strip()}"

        # Run cleanup script - it should switch to main automatically
        success, stdout, stderr = run_command(
            ["python3", str(test_script), "--dry-run", "--skip-fetch"],
            cwd=repo_path
        )

        # Script should succeed
        assert success, f"Script should succeed after switching to main. stdout: {stdout}, stderr: {stderr}"

        # Verify we're now on main branch
        success, stdout, _ = run_command(["git", "branch", "--show-current"], cwd=repo_path)
        assert success
        assert stdout.strip() == "main", f"Should be on main after script runs, got {stdout.strip()}"

        print("✓ test_switch_to_main_branch passed")


def test_change_to_repo_root():
    """Test that script changes to repository root if in subdirectory"""

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize repo
        run_command(["git", "init"], cwd=repo_path)
        run_command(["git", "config", "user.email", "test@example.com"], cwd=repo_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=repo_path)

        # Create initial commit on main
        test_file = repo_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=repo_path)

        # Copy the cleanup script to repo root and commit it
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script_main = repo_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script_main)
        test_script_main.chmod(0o755)
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Add cleanup script"], cwd=repo_path)

        # Create a subdirectory and commit it so it's tracked
        subdir = repo_path / "some" / "nested" / "directory"
        subdir.mkdir(parents=True)
        (subdir / ".gitkeep").write_text("")  # Make directory trackable
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Add subdirectory"], cwd=repo_path)

        # Run cleanup script from subdirectory - it should change to repo root
        # Use the script from the repo root (where it's committed)
        success, stdout, stderr = run_command(
            ["python3", str(test_script_main), "--dry-run", "--skip-fetch"],
            cwd=subdir
        )

        # Script should succeed even when run from subdirectory
        assert success, f"Script should succeed after changing to repo root. stdout: {stdout}, stderr: {stderr}"

        print("✓ test_change_to_repo_root passed")


def test_pull_latest_from_origin():
    """Test that script pulls latest from origin/main"""

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create two repos: origin and local clone
        origin_path = Path(tmpdir) / "origin"
        origin_path.mkdir()

        # Initialize origin repo
        run_command(["git", "init", "--bare"], cwd=origin_path)

        # Clone it
        clone_path = Path(tmpdir) / "clone"
        success, _, _ = run_command(
            ["git", "clone", str(origin_path), str(clone_path)]
        )
        assert success, "Failed to clone repo"

        # Configure clone
        run_command(["git", "config", "user.email", "test@example.com"], cwd=clone_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=clone_path)

        # Create initial commit on main in clone
        test_file = clone_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=clone_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=clone_path)
        run_command(["git", "push", "origin", "main"], cwd=clone_path)

        # Create another commit and push it to origin
        test_file.write_text("updated")
        run_command(["git", "add", "."], cwd=clone_path)
        run_command(["git", "commit", "-m", "Second commit"], cwd=clone_path)
        run_command(["git", "push", "origin", "main"], cwd=clone_path)

        # Get the latest commit on origin (this is what we want to be at after pull)
        success, origin_commit, _ = run_command(["git", "rev-parse", "HEAD"], cwd=clone_path)
        assert success
        origin_commit = origin_commit.strip()

        # Now reset local to one commit behind (simulate being behind origin)
        run_command(["git", "reset", "--hard", "HEAD~1"], cwd=clone_path)

        # Verify we're behind
        success, local_commit, _ = run_command(["git", "rev-parse", "HEAD"], cwd=clone_path)
        assert success
        assert local_commit.strip() != origin_commit, "Should be behind origin"

        # Copy the cleanup script to a temporary location OUTSIDE the repo
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        temp_script_dir = Path(tempfile.mkdtemp())
        temp_script = temp_script_dir / "git-cleanup-audit.py"
        shutil.copy(script_path, temp_script)
        temp_script.chmod(0o755)

        # Commit something else to push to origin
        dummy_file = clone_path / "dummy.txt"
        dummy_file.write_text("dummy")
        run_command(["git", "add", "."], cwd=clone_path)
        run_command(["git", "commit", "-m", "Add dummy file"], cwd=clone_path)

        # Push this commit so origin is ahead
        run_command(["git", "push", "origin", "main"], cwd=clone_path)

        # Get the new origin commit (this is what we want to pull to)
        success, final_origin_commit, _ = run_command(["git", "rev-parse", "HEAD"], cwd=clone_path)
        assert success
        final_origin_commit = final_origin_commit.strip()

        # Reset back one commit to simulate being behind again
        run_command(["git", "reset", "--hard", "HEAD~1"], cwd=clone_path)

        # Run cleanup script from outside the repo - it should pull latest from origin
        # Use the temp script and run it with the clone path as cwd
        success, stdout, stderr = run_command(
            ["python3", str(temp_script), "--dry-run"],
            cwd=clone_path
        )

        # Script should succeed
        assert success, f"Script should succeed after pulling. stdout: {stdout}, stderr: {stderr}"

        # Verify we're now at the latest commit from origin
        # First, let's see what origin/main is at
        success, origin_main_commit, _ = run_command(["git", "rev-parse", "origin/main"], cwd=clone_path)
        assert success
        origin_main_commit = origin_main_commit.strip()

        # Verify we're now at the same commit as origin/main
        success, local_commit, _ = run_command(["git", "rev-parse", "HEAD"], cwd=clone_path)
        assert success

        # After pull, we should be at the same commit as origin/main
        assert local_commit.strip() == origin_main_commit, \
            f"Should be at origin/main commit after pull. Expected {origin_main_commit}, got {local_commit.strip()}"

        print("✓ test_pull_latest_from_origin passed")


def test_preflight_order():
    """Test that new preflight checks happen BEFORE existing checks"""

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize repo
        run_command(["git", "init"], cwd=repo_path)
        run_command(["git", "config", "user.email", "test@example.com"], cwd=repo_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=repo_path)

        # Create initial commit on main
        test_file = repo_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=repo_path)

        # Create and switch to feature branch
        run_command(["git", "checkout", "-b", "feature/test"], cwd=repo_path)

        # Create uncommitted changes (this will trigger existing preflight check)
        test_file.write_text("uncommitted change")

        # Copy the cleanup script
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script = repo_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script)
        test_script.chmod(0o755)

        # Run cleanup script
        # It should:
        # 1. Switch to main (new preflight)
        # 2. Then check for uncommitted changes (existing preflight)
        # Since uncommitted changes exist, it should fail with exit code 2
        success, stdout, stderr = run_command(
            ["python3", str(test_script), "--dry-run", "--skip-fetch"],
            cwd=repo_path
        )

        # Should fail due to uncommitted changes
        assert not success, "Script should fail due to uncommitted changes"
        assert "Uncommitted changes detected" in stdout or "Uncommitted changes detected" in stderr, \
            f"Should report uncommitted changes. stdout: {stdout}, stderr: {stderr}"

        # But it should have switched to main BEFORE checking for changes
        success, current_branch, _ = run_command(["git", "branch", "--show-current"], cwd=repo_path)
        assert success
        assert current_branch.strip() == "main", \
            f"Should be on main even though script failed. Got {current_branch.strip()}"

        print("✓ test_preflight_order passed")


def test_switch_to_main_with_uncommitted_changes():
    """Test that switching to main fails gracefully if there are uncommitted changes"""

    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir) / "test-repo"
        repo_path.mkdir()

        # Initialize repo
        run_command(["git", "init"], cwd=repo_path)
        run_command(["git", "config", "user.email", "test@example.com"], cwd=repo_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=repo_path)

        # Create initial commit on main
        test_file = repo_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=repo_path)

        # Create and switch to feature branch
        run_command(["git", "checkout", "-b", "feature/test"], cwd=repo_path)

        # Make changes on feature branch
        test_file.write_text("feature changes")
        run_command(["git", "add", "."], cwd=repo_path)
        run_command(["git", "commit", "-m", "Feature commit"], cwd=repo_path)

        # Create uncommitted changes that would conflict with main
        test_file.write_text("uncommitted changes")

        # Copy the cleanup script
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script = repo_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script)
        test_script.chmod(0o755)

        # Run cleanup script - it should fail gracefully when trying to switch to main
        success, stdout, stderr = run_command(
            ["python3", str(test_script), "--dry-run", "--skip-fetch"],
            cwd=repo_path
        )

        # Should fail - either when switching to main or at uncommitted changes check
        assert not success, "Script should fail due to uncommitted changes"

        # Verify error message is helpful
        combined_output = stdout + stderr
        assert ("uncommitted" in combined_output.lower() or
                "changes" in combined_output.lower() or
                "switch" in combined_output.lower()), \
            f"Should provide helpful error message. Output: {combined_output}"

        print("✓ test_switch_to_main_with_uncommitted_changes passed")


def test_pull_with_conflicts():
    """Test that pull fails gracefully if there are conflicts"""

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create two repos: origin and local clone
        origin_path = Path(tmpdir) / "origin"
        origin_path.mkdir()

        # Initialize origin repo
        run_command(["git", "init", "--bare"], cwd=origin_path)

        # Clone it
        clone_path = Path(tmpdir) / "clone"
        success, _, _ = run_command(
            ["git", "clone", str(origin_path), str(clone_path)]
        )
        assert success, "Failed to clone repo"

        # Configure clone
        run_command(["git", "config", "user.email", "test@example.com"], cwd=clone_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=clone_path)

        # Create initial commit on main in clone
        test_file = clone_path / "test.txt"
        test_file.write_text("initial")
        run_command(["git", "add", "."], cwd=clone_path)
        run_command(["git", "commit", "-m", "Initial commit"], cwd=clone_path)
        run_command(["git", "push", "origin", "main"], cwd=clone_path)

        # Create divergent history
        # In clone: make a commit
        test_file.write_text("local change")
        run_command(["git", "add", "."], cwd=clone_path)
        run_command(["git", "commit", "-m", "Local commit"], cwd=clone_path)

        # In origin: make a conflicting commit (using another clone)
        clone2_path = Path(tmpdir) / "clone2"
        run_command(["git", "clone", str(origin_path), str(clone2_path)])
        run_command(["git", "config", "user.email", "test@example.com"], cwd=clone2_path)
        run_command(["git", "config", "user.name", "Test User"], cwd=clone2_path)
        test_file2 = clone2_path / "test.txt"
        test_file2.write_text("remote change")
        run_command(["git", "add", "."], cwd=clone2_path)
        run_command(["git", "commit", "-m", "Remote commit"], cwd=clone2_path)
        run_command(["git", "push", "origin", "main"], cwd=clone2_path)

        # Now clone has diverged from origin
        # Copy the cleanup script
        script_path = Path("/home/eru_admin/repos/airflow-data-platform/git-cleanup-audit.py")
        test_script = clone_path / "git-cleanup-audit.py"
        shutil.copy(script_path, test_script)
        test_script.chmod(0o755)

        # Run cleanup script - it should fail gracefully when trying to pull
        success, stdout, stderr = run_command(
            ["python3", str(test_script), "--dry-run"],
            cwd=clone_path
        )

        # Should fail due to pull conflict
        assert not success, "Script should fail due to pull conflict"

        # Verify error message mentions pull or merge issue
        combined_output = stdout + stderr
        assert ("pull" in combined_output.lower() or
                "merge" in combined_output.lower() or
                "conflict" in combined_output.lower() or
                "diverged" in combined_output.lower()), \
            f"Should provide helpful error about pull issue. Output: {combined_output}"

        print("✓ test_pull_with_conflicts passed")


def run_all_tests():
    """Run all tests and report results"""
    tests = [
        ("Switch to main branch", test_switch_to_main_branch),
        ("Change to repo root", test_change_to_repo_root),
        ("Pull latest from origin", test_pull_latest_from_origin),
        ("Preflight order", test_preflight_order),
        ("Switch with uncommitted changes", test_switch_to_main_with_uncommitted_changes),
        ("Pull with conflicts", test_pull_with_conflicts),
    ]

    print("=" * 60)
    print("Running TDD tests for git-cleanup-audit preflight checks")
    print("=" * 60)
    print()

    failed = []

    for name, test_func in tests:
        try:
            print(f"Running: {name}")
            test_func()
            print()
        except AssertionError as e:
            print(f"✗ FAILED: {name}")
            print(f"  {e}")
            print()
            failed.append((name, e))
        except Exception as e:
            print(f"✗ ERROR: {name}")
            print(f"  {e}")
            print()
            failed.append((name, e))

    print("=" * 60)
    if failed:
        print(f"FAILED: {len(failed)}/{len(tests)} tests failed")
        for name, error in failed:
            print(f"  - {name}: {error}")
        return 1
    else:
        print(f"SUCCESS: All {len(tests)} tests passed!")
        return 0


if __name__ == "__main__":
    exit(run_all_tests())
