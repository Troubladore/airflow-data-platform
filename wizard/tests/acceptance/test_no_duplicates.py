"""Test that prompts are not duplicated in terminal output."""

import subprocess

def test_prompts_shown_once_not_twice():
    """Each prompt should appear exactly once in output."""
    # Run actual command
    result = subprocess.run(
        ['./platform', 'setup'],
        input='\n\n\n\n\n\n\n\n',  # Press Enter 8 times
        capture_output=True,
        text=True,
        timeout=15,
        cwd='/home/troubladore/repos/airflow-data-platform/.worktrees/data-driven-wizard'
    )

    output = result.stdout

    # Check for duplicates
    assert output.count('Install OpenMetadata?') == 1, \
        f"'Install OpenMetadata?' appears {output.count('Install OpenMetadata?')} times"
    assert output.count('Install Kerberos?') == 1, \
        f"'Install Kerberos?' appears multiple times"
    assert output.count('PostgreSQL image') == 1, \
        f"'PostgreSQL image' appears multiple times"
