"""Test that {variables} are interpolated in prompts."""

import subprocess

def test_no_placeholder_variables_in_output():
    """Variables like {current_value} should be replaced, not shown literally."""
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

    # Check that no {placeholders} remain
    assert '{current_value}' not in output, \
        "Placeholders should be interpolated, not shown literally"
    assert '{' not in output or 'PostgreSQL image [' not in output, \
        "All {variables} should be replaced with actual values"
