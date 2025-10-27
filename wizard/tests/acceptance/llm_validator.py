"""LLM-based terminal output validation framework.

This module provides utilities for running wizard commands and evaluating
their terminal output quality using LLM agents. It captures real subprocess
output and dispatches evaluation to ensure UX quality matches human expectations.
"""

import subprocess
from pathlib import Path
from typing import Tuple, Dict, Any


def run_wizard_and_capture(
    command: list[str],
    inputs: str,
    timeout: int = 15
) -> Tuple[str, str, int]:
    """Run wizard command and capture real terminal output.

    This function runs an actual wizard command via subprocess, captures
    stdout/stderr as users would see it, and returns the output for evaluation.

    Args:
        command: Command to run as list (e.g., ['./platform', 'setup'])
        inputs: String to send to stdin (e.g., '\\n\\n\\n' for multiple Enters)
        timeout: Timeout in seconds (default: 15)

    Returns:
        Tuple of (stdout, stderr, returncode)

    Example:
        >>> stdout, stderr, code = run_wizard_and_capture(
        ...     command=['./platform', 'setup'],
        ...     inputs='\\n' * 8  # Press Enter 8 times
        ... )
        >>> assert 'Install OpenMetadata?' in stdout
    """
    # Get repository root (4 levels up from this file)
    repo_root = Path(__file__).parent.parent.parent.parent

    try:
        result = subprocess.run(
            command,
            input=inputs,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(repo_root)
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired as e:
        # Return partial output if timeout occurs
        stdout = e.stdout.decode('utf-8') if e.stdout else ''
        stderr = e.stderr.decode('utf-8') if e.stderr else ''
        return stdout, stderr, -1


def evaluate_ux_with_llm(
    scenario_name: str,
    stdout: str,
    stderr: str,
    returncode: int,
    ux_principles: str
) -> Dict[str, Any]:
    """Dispatch LLM agent to evaluate terminal output quality.

    This function would use the Task tool to dispatch a general-purpose agent
    that evaluates the terminal output against UX principles. The agent acts
    as a human reviewer, checking formatting, consistency, clarity, and overall
    user experience quality.

    In the current implementation (Task 25d), this returns a structured dict
    that tests can validate. Full LLM dispatch will be implemented in Task 25f.

    Args:
        scenario_name: Description of test scenario (e.g., "Setup - all defaults")
        stdout: Standard output captured from command
        stderr: Standard error captured from command
        returncode: Exit code from command
        ux_principles: UX standards document content (from ux_principles.md)

    Returns:
        Dictionary with evaluation results:
        {
            'passed': bool,           # Overall pass/fail
            'overall_grade': str,     # A-F grade
            'issues': list[str],      # Specific problems found
            'positive_aspects': list[str],  # Things done well
            'user_quote': str         # What user would say about this
        }

    Example:
        >>> principles = Path('ux_principles.md').read_text()
        >>> result = evaluate_ux_with_llm(
        ...     scenario_name="Setup wizard - all defaults",
        ...     stdout=captured_output,
        ...     stderr='',
        ...     returncode=0,
        ...     ux_principles=principles
        ... )
        >>> assert result['passed']
        >>> assert result['overall_grade'] in ['A', 'B']
    """
    # TODO (Task 25f): Implement actual LLM dispatch using Task tool
    # For now, return structure that can be validated by tests

    # Analyze output for common issues
    issues = []
    positive_aspects = []

    # Check for duplicate prompts
    if stdout.count('Install OpenMetadata?') > 1:
        issues.append("Duplicate prompt: 'Install OpenMetadata?' appears multiple times")
    else:
        positive_aspects.append("Each prompt shown exactly once")

    # Check for literal placeholders
    if '{current_value}' in stdout or '{' in stdout:
        issues.append("Literal placeholder variables shown instead of actual values")
    else:
        positive_aspects.append("Variables properly interpolated")

    # Check for boolean format
    if '[False]' in stdout or '[True]' in stdout:
        issues.append("Boolean defaults shown as [False]/[True] instead of [y/N] format")
    else:
        positive_aspects.append("Boolean prompts use user-friendly [y/N] format")

    # Check for run-together text (basic heuristic)
    if '?:' in stdout and stdout.count('?:') > 2:
        issues.append("Prompts may be running together without proper newlines")

    # Determine grade based on issues
    if len(issues) == 0:
        grade = 'A'
        passed = True
        user_quote = "This is professional and polished. Easy to use."
    elif len(issues) == 1:
        grade = 'B'
        passed = True
        user_quote = "Works well, minor issues noticed."
    elif len(issues) == 2:
        grade = 'C'
        passed = False
        user_quote = "Functional but rough around the edges."
    else:
        grade = 'F'
        passed = False
        user_quote = "This looks broken. Confusing to use."

    return {
        'passed': passed,
        'overall_grade': grade,
        'issues': issues,
        'positive_aspects': positive_aspects,
        'user_quote': user_quote,
        'scenario': scenario_name,
        'returncode': returncode
    }


def format_evaluation_report(evaluation: Dict[str, Any]) -> str:
    """Format evaluation results as a readable report.

    Args:
        evaluation: Dictionary returned by evaluate_ux_with_llm()

    Returns:
        Formatted string report
    """
    lines = [
        f"\n{'='*60}",
        f"UX Evaluation Report: {evaluation['scenario']}",
        f"{'='*60}",
        f"\nOverall Grade: {evaluation['overall_grade']}",
        f"Status: {'PASS' if evaluation['passed'] else 'FAIL'}",
        f"Exit Code: {evaluation['returncode']}",
    ]

    if evaluation['positive_aspects']:
        lines.append("\n✓ Positive Aspects:")
        for aspect in evaluation['positive_aspects']:
            lines.append(f"  - {aspect}")

    if evaluation['issues']:
        lines.append("\n✗ Issues Found:")
        for issue in evaluation['issues']:
            lines.append(f"  - {issue}")

    if evaluation['user_quote']:
        lines.append(f"\nUser Perspective: \"{evaluation['user_quote']}\"")

    lines.append(f"\n{'='*60}\n")

    return '\n'.join(lines)
