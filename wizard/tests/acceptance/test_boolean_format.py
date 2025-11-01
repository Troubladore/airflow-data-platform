"""Test that boolean prompts show [y/N] not [False]."""

import subprocess

def test_boolean_defaults_show_yn_format():
    """Boolean prompts should show [y/N] format, not [False]."""
    import os
    # Use project root (2 levels up from wizard/tests/acceptance)
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    result = subprocess.run(
        ['./platform', 'setup'],
        input='\n\n\n\n\n\n\n\n',
        capture_output=True,
        text=True,
        timeout=15,
        cwd=project_root
    )

    output = result.stdout

    # Check for proper format
    assert '[y/N]' in output or '[y/n]' in output, \
        "Boolean prompts should show [y/N] format"

    # Check that boolean values aren't shown literally
    assert '[False]' not in output, \
        "Should not show [False] - use [y/N] instead"
    assert '[True]' not in output, \
        "Should not show [True] - use [y/N] instead"
