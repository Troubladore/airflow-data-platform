"""Permanent UX validation tests using LLM evaluation.

These tests run actual ./platform commands via subprocess, capture real
terminal output, and evaluate UX quality using LLM agents. They validate
what users actually see, not just internal logic.
"""

import pytest
from pathlib import Path
from .llm_validator import (
    run_wizard_and_capture,
    evaluate_ux_with_llm,
    format_evaluation_report
)


@pytest.mark.acceptance
class TestSetupWizardUX:
    """UX validation for setup wizard.

    These tests ensure the setup wizard provides excellent user experience
    with proper formatting, clear prompts, and professional appearance.
    """

    def test_setup_all_defaults_ux(self):
        """Setup with all defaults should have excellent UX.

        This is the most common path - user presses Enter repeatedly.
        It must be flawless: clean prompts, proper formatting, professional.
        """
        # Run actual command
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'setup'],
            inputs='\n' * 8  # Press Enter 8 times for all defaults
        )

        # Load UX principles
        principles_path = Path(__file__).parent / 'ux_principles.md'
        principles = principles_path.read_text()

        # LLM evaluation
        result = evaluate_ux_with_llm(
            scenario_name="Setup wizard - all defaults",
            stdout=stdout,
            stderr=stderr,
            returncode=code,
            ux_principles=principles
        )

        # Print detailed report for debugging
        print(format_evaluation_report(result))

        # Assert quality standards
        assert result['passed'], \
            f"UX issues found:\n{format_evaluation_report(result)}"
        assert result['overall_grade'] in ['A', 'B'], \
            f"UX grade {result['overall_grade']} too low. Report:\n{format_evaluation_report(result)}"

    def test_setup_custom_values_ux(self):
        """Setup with custom values should have excellent UX.

        When users customize configuration, prompts must still be clear,
        formatting consistent, and experience professional.
        """
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'setup'],
            inputs='y\nn\ny\npostgres:16\ny\ntrust\n\n5433\n'
        )

        principles_path = Path(__file__).parent / 'ux_principles.md'
        principles = principles_path.read_text()

        result = evaluate_ux_with_llm(
            scenario_name="Setup wizard - custom values",
            stdout=stdout,
            stderr=stderr,
            returncode=code,
            ux_principles=principles
        )

        print(format_evaluation_report(result))

        assert result['passed'], \
            f"UX issues found:\n{format_evaluation_report(result)}"

    def test_setup_output_has_no_duplicates(self):
        """Verify each prompt appears exactly once in output.

        This is a regression test for the duplicate prompt bug where
        every question was shown twice.
        """
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'setup'],
            inputs='\n' * 8
        )

        # Check specific prompts appear exactly once
        prompts_to_check = [
            'Install OpenMetadata?',
            'Install Kerberos?',
            'PostgreSQL image'
        ]

        for prompt in prompts_to_check:
            count = stdout.count(prompt)
            assert count == 1, \
                f"'{prompt}' appears {count} times (expected 1). Output:\n{stdout}"

    def test_setup_output_has_proper_boolean_format(self):
        """Verify boolean prompts show [y/N] format, not [False].

        This is a regression test for boolean format bug where prompts
        showed technical [False]/[True] instead of user-friendly format.
        """
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'setup'],
            inputs='\n' * 8
        )

        # Check for proper format
        assert '[y/N]' in stdout or '[y/n]' in stdout or '[Y/n]' in stdout, \
            f"Boolean prompts should show [y/N] format. Output:\n{stdout}"

        # Check that boolean values aren't shown literally
        assert '[False]' not in stdout, \
            f"Should not show [False] - use [y/N] instead. Output:\n{stdout}"
        assert '[True]' not in stdout, \
            f"Should not show [True] - use [y/N] instead. Output:\n{stdout}"

    def test_setup_output_has_interpolated_variables(self):
        """Verify {variables} are replaced with actual values.

        This is a regression test for interpolation bug where prompts
        showed {current_value} literally instead of the actual value.
        """
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'setup'],
            inputs='\n' * 8
        )

        # Check that no {placeholders} remain
        assert '{current_value}' not in stdout, \
            f"Placeholders should be interpolated. Output:\n{stdout}"

        # More general check - look for any remaining placeholders
        # (allow single { in box borders but catch {word} patterns)
        import re
        placeholder_pattern = r'\{[a-zA-Z_][a-zA-Z0-9_]*\}'
        placeholders = re.findall(placeholder_pattern, stdout)

        assert len(placeholders) == 0, \
            f"Found uninterpolated placeholders: {placeholders}. Output:\n{stdout}"


@pytest.mark.acceptance
class TestCleanSlateWizardUX:
    """UX validation for clean-slate wizard.

    These tests ensure the clean-slate wizard provides clear messaging
    about system state and actions taken.
    """

    def test_clean_slate_empty_system_ux(self):
        """Clean-slate with empty system should have clear messaging.

        When system is already clean, message should be clear and
        reassuring, not confusing or error-like.
        """
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'clean-slate'],
            inputs=''
        )

        principles_path = Path(__file__).parent / 'ux_principles.md'
        principles = principles_path.read_text()

        result = evaluate_ux_with_llm(
            scenario_name="Clean-slate - empty system",
            stdout=stdout,
            stderr=stderr,
            returncode=code,
            ux_principles=principles
        )

        print(format_evaluation_report(result))

        # Focus on UX quality, not exit code (wizard may exit with 1 when nothing to clean)
        # Should have clear messaging about system state
        assert result['passed'], \
            f"UX issues found:\n{format_evaluation_report(result)}"


@pytest.mark.acceptance
class TestMigrationWizardUX:
    """UX validation for migration wizard.

    These tests ensure migration prompts are clear and guide users
    through the configuration migration process.
    """

    def test_migration_wizard_ux_quality(self):
        """Migration wizard should have excellent UX.

        Migration is potentially confusing, so UX must be especially
        clear with good explanations and proper formatting.
        """
        # Note: Migration wizard may require existing config file
        # For now, test basic invocation to ensure no crashes
        stdout, stderr, code = run_wizard_and_capture(
            command=['./platform', 'migrate-to-platform-config'],
            inputs='\n',
            timeout=10
        )

        # Basic sanity checks
        assert stdout or stderr, \
            "Migration wizard should produce output"

        # If it runs, it shouldn't have formatting issues
        assert '{current_value}' not in stdout, \
            "Variables should be interpolated"
        assert '[False]' not in stdout, \
            "Boolean format should be user-friendly"


# Utility test to verify framework is working
@pytest.mark.acceptance
def test_llm_validator_framework_works():
    """Verify the LLM validator framework itself is functional.

    This meta-test ensures our testing infrastructure works correctly
    before we rely on it for UX validation.
    """
    # Create mock output
    mock_stdout = """
Install OpenMetadata? [y/N]:
Install Kerberos? [y/N]:
PostgreSQL image [postgres:17.5-alpine]:
"""

    principles_path = Path(__file__).parent / 'ux_principles.md'
    principles = principles_path.read_text()

    # Evaluate mock output
    result = evaluate_ux_with_llm(
        scenario_name="Framework test",
        stdout=mock_stdout,
        stderr='',
        returncode=0,
        ux_principles=principles
    )

    # Verify structure
    assert 'passed' in result
    assert 'overall_grade' in result
    assert 'issues' in result
    assert 'positive_aspects' in result
    assert isinstance(result['passed'], bool)
    assert result['overall_grade'] in ['A', 'B', 'C', 'D', 'F']

    # This good output should pass
    assert result['passed'] is True
    assert result['overall_grade'] in ['A', 'B']
