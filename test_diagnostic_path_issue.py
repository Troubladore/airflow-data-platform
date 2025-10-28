#!/usr/bin/env python3
"""
Test the diagnostic path issue - this is likely the root cause of
"No such file or directory" error in diagnostics.
"""

import subprocess
import os

def test_diagnostic_path_resolution():
    """Test how the diagnostic path check fails."""
    print("=" * 60)
    print("Testing Diagnostic Path Resolution Issue")
    print("=" * 60)

    print("\nCurrent working directory:", os.getcwd())

    # The setup-pagila.sh script clones pagila to:
    # PAGILA_DIR="$(dirname "$(dirname "$PLATFORM_DIR")")/pagila"
    # Where PLATFORM_DIR is platform-bootstrap

    # So if we're in .worktrees/fix-pagila-corp-setup:
    # platform-bootstrap is at ./platform-bootstrap
    # pagila gets cloned to ../../pagila (relative to platform-bootstrap)
    # which is ../pagila (relative to worktree root)

    print("\n1. Path calculation from setup-pagila.sh:")
    platform_dir = os.path.abspath("./platform-bootstrap")
    print(f"   PLATFORM_DIR = {platform_dir}")

    parent_of_platform = os.path.dirname(platform_dir)
    print(f"   dirname(PLATFORM_DIR) = {parent_of_platform}")

    parent_of_parent = os.path.dirname(parent_of_platform)
    print(f"   dirname(dirname(PLATFORM_DIR)) = {parent_of_parent}")

    pagila_dir = os.path.join(parent_of_parent, "pagila")
    print(f"   PAGILA_DIR = {pagila_dir}")

    print("\n2. Checking if pagila exists at calculated location:")
    if os.path.exists(pagila_dir):
        print(f"   ✓ Pagila exists at: {pagila_dir}")
    else:
        print(f"   ✗ Pagila NOT found at: {pagila_dir}")

    print("\n3. The diagnostic issue:")
    print("   The wizard runs from worktree root")
    print("   The diagnostic checks: test -d ../pagila")

    # From worktree root, ../pagila would be:
    from_worktree = os.path.abspath("../pagila")
    print(f"   From worktree, ../pagila resolves to: {from_worktree}")
    print(f"   Does this path exist? {os.path.exists(from_worktree)}")

    print("\n4. The mismatch:")
    print(f"   Pagila is actually at: {pagila_dir}")
    print(f"   Diagnostic looks at:   {from_worktree}")
    print(f"   These are {'the same' if pagila_dir == from_worktree else 'DIFFERENT'}!")

    # Now let's check what the diagnostic should be checking
    print("\n5. Correct path for diagnostic:")
    # If wizard runs from worktree root, and pagila is cloned to
    # /home/eru_admin/repos/airflow-data-platform/pagila
    # Then from worktree root, it should check:
    correct_path_from_worktree = "../../pagila"
    print(f"   Should check: {correct_path_from_worktree}")
    abs_correct = os.path.abspath(correct_path_from_worktree)
    print(f"   Which resolves to: {abs_correct}")
    print(f"   Does this exist? {os.path.exists(abs_correct)}")

    print("\n6. Summary of the bug:")
    print("   • setup-pagila.sh clones to: /home/eru_admin/repos/airflow-data-platform/pagila")
    print("   • This is ../../pagila from the worktree")
    print("   • But diagnostic checks ../pagila from worktree")
    print("   • This causes 'No such file or directory' error!")

if __name__ == "__main__":
    test_diagnostic_path_resolution()