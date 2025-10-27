#!/usr/bin/env python3
"""
Terminal UX Quality Testing for Platform Setup Wizard
=====================================================

Tests three scenarios with pexpect to capture actual terminal output:
1. All defaults (answer N to everything)
2. Custom values (answer Y to services, provide custom config)
3. Validation error recovery (test re-prompting on invalid selections)

Evaluates output against UX criteria:
- Prompts clear?
- [y/N] format correct?
- Progress messages shown?
- No jargon?
- Professional appearance?

Assigns letter grades A/B/C/D/F with specific issues and recommendations.
"""

import os
import sys
import pexpect
import re
import time
from dataclasses import dataclass
from typing import List, Tuple, Optional


@dataclass
class UXIssue:
    """Represents a UX quality issue found during testing"""
    severity: str  # "critical", "major", "minor"
    category: str  # "prompts", "format", "progress", "jargon", "appearance"
    description: str
    location: str  # Where in the flow this occurred
    line_number: Optional[int] = None


@dataclass
class TestScenario:
    """Test scenario configuration and results"""
    name: str
    description: str
    interactions: List[Tuple[str, str]]  # (expected_prompt, response)
    captured_output: str = ""
    issues: List[UXIssue] = None
    grade: str = ""

    def __post_init__(self):
        if self.issues is None:
            self.issues = []


class WizardUXTester:
    """Tests terminal UX quality of the platform setup wizard"""

    def __init__(self, wizard_path: str):
        self.wizard_path = wizard_path
        self.scenarios: List[TestScenario] = []

    def run_scenario(self, scenario: TestScenario, timeout: int = 30) -> bool:
        """Run a test scenario and capture output"""
        print(f"\n{'='*70}")
        print(f"Running Scenario: {scenario.name}")
        print(f"{'='*70}")

        try:
            # Spawn the wizard process with NO_COLOR to get clean output
            env = os.environ.copy()
            env['NO_COLOR'] = '1'  # Request plain ASCII output

            child = pexpect.spawn(
                'bash',
                [self.wizard_path],
                timeout=timeout,
                encoding='utf-8',
                env=env
            )

            # Set log file to capture all output
            output_lines = []

            class OutputCapture:
                def write(self, s):
                    output_lines.append(s)
                def flush(self):
                    pass

            child.logfile_read = OutputCapture()

            # Process each interaction
            for expected, response in scenario.interactions:
                try:
                    # Wait for expected prompt
                    if expected:
                        print(f"  Waiting for: {expected[:50]}...")
                        child.expect(expected, timeout=10)

                    # Send response
                    if response:
                        print(f"  Responding: {response}")
                        child.sendline(response)
                        time.sleep(0.3)  # Give time for response to be processed

                except pexpect.TIMEOUT:
                    print(f"  TIMEOUT waiting for: {expected[:50]}")
                    # Continue anyway to capture what we got
                    if response:
                        child.sendline(response)

                except pexpect.EOF:
                    print(f"  EOF reached")
                    break

            # Try to let it finish gracefully
            try:
                child.expect(pexpect.EOF, timeout=5)
            except pexpect.TIMEOUT:
                child.close(force=True)

            # Store captured output
            scenario.captured_output = ''.join(output_lines)

            print(f"\n  Captured {len(scenario.captured_output)} characters of output")
            return True

        except Exception as e:
            print(f"  ERROR: {e}")
            scenario.captured_output = ''.join(output_lines) if 'output_lines' in locals() else ""
            return False

    def analyze_ux_quality(self, scenario: TestScenario) -> None:
        """Analyze captured output for UX quality issues"""
        output = scenario.captured_output
        lines = output.split('\n')

        print(f"\n{'='*70}")
        print(f"Analyzing UX Quality: {scenario.name}")
        print(f"{'='*70}")

        # 1. Check prompt clarity
        self._check_prompt_clarity(scenario, lines)

        # 2. Check [y/N] format
        self._check_yn_format(scenario, lines)

        # 3. Check progress messages
        self._check_progress_messages(scenario, lines)

        # 4. Check for jargon
        self._check_jargon(scenario, lines)

        # 5. Check professional appearance
        self._check_appearance(scenario, lines)

        # Calculate grade
        scenario.grade = self._calculate_grade(scenario.issues)

        print(f"\n  Found {len(scenario.issues)} issues")
        print(f"  Grade: {scenario.grade}")

    def _check_prompt_clarity(self, scenario: TestScenario, lines: List[str]) -> None:
        """Check if prompts are clear and understandable"""
        # Look for prompts (lines ending with ?, :, or containing "press enter")
        prompt_lines = [
            (i, line) for i, line in enumerate(lines)
            if '?' in line or 'Press Enter' in line or 'press Enter' in line
        ]

        for line_num, line in prompt_lines:
            # Check for overly long prompts (> 100 chars)
            if len(line.strip()) > 100:
                scenario.issues.append(UXIssue(
                    severity="minor",
                    category="prompts",
                    description=f"Prompt too long ({len(line.strip())} chars): {line.strip()[:60]}...",
                    location=f"Line {line_num}",
                    line_number=line_num
                ))

            # Check for unclear phrasing (double negatives, complex words)
            unclear_patterns = [
                (r'not.*not', "Double negative detected"),
                (r'don\'t.*not', "Double negative detected"),
                (r'utilize|leverage', "Use simpler word (use instead of utilize/leverage)"),
            ]

            for pattern, message in unclear_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    scenario.issues.append(UXIssue(
                        severity="minor",
                        category="prompts",
                        description=f"{message}: {line.strip()[:60]}",
                        location=f"Line {line_num}",
                        line_number=line_num
                    ))

    def _check_yn_format(self, scenario: TestScenario, lines: List[str]) -> None:
        """Check if yes/no prompts follow [y/N] format correctly"""
        # Look for yes/no questions
        for i, line in enumerate(lines):
            # Should have [y/N] or [Y/n] format
            if '?' in line and any(word in line.lower() for word in ['enable', 'configure', 'want', 'use']):
                # Check if it has proper format
                has_yn = re.search(r'\[([yY])/([nN])\]', line)

                if not has_yn:
                    # Missing [y/N] format
                    scenario.issues.append(UXIssue(
                        severity="major",
                        category="format",
                        description=f"Yes/no question missing [y/N] format: {line.strip()[:60]}",
                        location=f"Line {i}",
                        line_number=i
                    ))
                else:
                    # Check default is indicated correctly
                    y, n = has_yn.groups()
                    if y.isupper() and n.isupper():
                        scenario.issues.append(UXIssue(
                            severity="minor",
                            category="format",
                            description=f"Unclear default in [Y/N] - should be [y/N] or [Y/n]: {line.strip()[:60]}",
                            location=f"Line {i}",
                            line_number=i
                        ))

    def _check_progress_messages(self, scenario: TestScenario, lines: List[str]) -> None:
        """Check if progress messages are shown appropriately"""
        # Look for progress indicators
        progress_keywords = [
            'detecting', 'checking', 'setting up', 'configuring',
            'starting', 'creating', 'loading', 'installing',
            'complete', 'success', 'done'
        ]

        progress_lines = [
            line for line in lines
            if any(kw in line.lower() for kw in progress_keywords)
        ]

        # Should have reasonable progress messages
        if len(progress_lines) < 3:
            scenario.issues.append(UXIssue(
                severity="major",
                category="progress",
                description=f"Insufficient progress messages ({len(progress_lines)} found)",
                location="Overall flow"
            ))

        # Check for progress without context
        for i, line in enumerate(lines):
            if any(kw in line.lower() for kw in ['starting', 'configuring', 'setting up']):
                # Should say WHAT is being started/configured
                if len(line.strip()) < 20:
                    scenario.issues.append(UXIssue(
                        severity="minor",
                        category="progress",
                        description=f"Progress message lacks context: {line.strip()}",
                        location=f"Line {i}",
                        line_number=i
                    ))

    def _check_jargon(self, scenario: TestScenario, lines: List[str]) -> None:
        """Check for technical jargon without explanation"""
        # Common jargon that should be explained
        jargon_terms = {
            'kerberos': 'authentication protocol',
            'openmetadata': 'metadata catalog',
            'opensearch': 'search engine',
            'artifactory': 'artifact repository',
            'pypi': 'Python package repository',
            'wsinterop': 'WSL interop',
            'kinit': 'Kerberos initialization',
            'klist': 'Kerberos ticket list',
            'oltp': 'transactional database',
        }

        for i, line in enumerate(lines):
            for term, explanation in jargon_terms.items():
                if term in line.lower():
                    # Check if explanation is nearby (within 3 lines)
                    context = ' '.join(lines[max(0, i-2):min(len(lines), i+3)]).lower()

                    # If it's just the term without context, flag it
                    if explanation not in context and len(line.strip().split()) < 5:
                        scenario.issues.append(UXIssue(
                            severity="minor",
                            category="jargon",
                            description=f"Jargon term '{term}' may need explanation",
                            location=f"Line {i}",
                            line_number=i
                        ))

    def _check_appearance(self, scenario: TestScenario, lines: List[str]) -> None:
        """Check professional appearance of output"""
        # Check for inconsistent spacing
        blank_line_runs = []
        blank_count = 0

        for i, line in enumerate(lines):
            if not line.strip():
                blank_count += 1
            else:
                if blank_count > 3:
                    blank_line_runs.append((i - blank_count, blank_count))
                blank_count = 0

        for start_line, count in blank_line_runs:
            scenario.issues.append(UXIssue(
                severity="minor",
                category="appearance",
                description=f"Excessive blank lines ({count} consecutive)",
                location=f"Lines {start_line}-{start_line + count}",
                line_number=start_line
            ))

        # Check for inconsistent section formatting
        section_markers = []
        for i, line in enumerate(lines):
            if line.strip().startswith('===') or line.strip().startswith('---'):
                section_markers.append((i, line.strip()[0]))

        # Check if section markers are consistent
        if section_markers:
            marker_types = [m[1] for m in section_markers]
            if len(set(marker_types)) > 2:
                scenario.issues.append(UXIssue(
                    severity="minor",
                    category="appearance",
                    description="Inconsistent section divider styles",
                    location="Multiple locations"
                ))

        # Check for proper capitalization in headings
        for i, line in enumerate(lines):
            if line.strip().endswith(':') and len(line.strip().split()) <= 5:
                # Likely a heading
                if not line.strip()[0].isupper():
                    scenario.issues.append(UXIssue(
                        severity="minor",
                        category="appearance",
                        description=f"Heading should be capitalized: {line.strip()}",
                        location=f"Line {i}",
                        line_number=i
                    ))

    def _calculate_grade(self, issues: List[UXIssue]) -> str:
        """Calculate letter grade based on issues found"""
        # Weight issues by severity
        score = 100

        for issue in issues:
            if issue.severity == "critical":
                score -= 20
            elif issue.severity == "major":
                score -= 10
            elif issue.severity == "minor":
                score -= 3

        # Convert to letter grade
        if score >= 95:
            return "A+"
        elif score >= 90:
            return "A"
        elif score >= 85:
            return "B+"
        elif score >= 80:
            return "B"
        elif score >= 75:
            return "C+"
        elif score >= 70:
            return "C"
        elif score >= 65:
            return "D+"
        elif score >= 60:
            return "D"
        else:
            return "F"

    def generate_report(self) -> str:
        """Generate comprehensive UX quality report"""
        report = []
        report.append("\n" + "="*80)
        report.append("PLATFORM SETUP WIZARD - TERMINAL UX QUALITY REPORT")
        report.append("="*80)

        for scenario in self.scenarios:
            report.append(f"\n{'─'*80}")
            report.append(f"SCENARIO: {scenario.name}")
            report.append(f"{'─'*80}")
            report.append(f"Description: {scenario.description}")
            report.append(f"GRADE: {scenario.grade}")
            report.append(f"\nIssues Found: {len(scenario.issues)}")

            # Group issues by category
            by_category = {}
            for issue in scenario.issues:
                if issue.category not in by_category:
                    by_category[issue.category] = []
                by_category[issue.category].append(issue)

            for category, issues in sorted(by_category.items()):
                report.append(f"\n  {category.upper()} ({len(issues)} issues):")
                for issue in issues:
                    severity_marker = {
                        "critical": "[!!!]",
                        "major": "[!!]",
                        "minor": "[!]"
                    }.get(issue.severity, "[?]")
                    report.append(f"    {severity_marker} {issue.description}")
                    report.append(f"         Location: {issue.location}")

        # Overall assessment
        report.append(f"\n{'='*80}")
        report.append("OVERALL ASSESSMENT")
        report.append("="*80)

        all_issues = []
        for scenario in self.scenarios:
            all_issues.extend(scenario.issues)

        total_critical = len([i for i in all_issues if i.severity == "critical"])
        total_major = len([i for i in all_issues if i.severity == "major"])
        total_minor = len([i for i in all_issues if i.severity == "minor"])

        report.append(f"\nTotal Issues: {len(all_issues)}")
        report.append(f"  Critical: {total_critical}")
        report.append(f"  Major: {total_major}")
        report.append(f"  Minor: {total_minor}")

        # Recommendations
        report.append(f"\n{'─'*80}")
        report.append("RECOMMENDATIONS")
        report.append("─"*80)

        recommendations = self._generate_recommendations(all_issues)
        for i, rec in enumerate(recommendations, 1):
            report.append(f"\n{i}. {rec}")

        return '\n'.join(report)

    def _generate_recommendations(self, issues: List[UXIssue]) -> List[str]:
        """Generate specific recommendations based on issues found"""
        recommendations = []

        # Group by category
        by_category = {}
        for issue in issues:
            if issue.category not in by_category:
                by_category[issue.category] = []
            by_category[issue.category].append(issue)

        # Generate category-specific recommendations
        if "format" in by_category:
            recommendations.append(
                "Ensure all yes/no questions consistently use [y/N] format with "
                "default clearly indicated by capital letter."
            )

        if "prompts" in by_category:
            recommendations.append(
                "Keep prompts concise (under 80 characters) and use simple, "
                "direct language. Avoid double negatives."
            )

        if "progress" in by_category:
            recommendations.append(
                "Add more progress messages to keep users informed. Each message "
                "should clearly state what is being done."
            )

        if "jargon" in by_category:
            recommendations.append(
                "Provide brief explanations for technical terms when they first "
                "appear, or link to documentation."
            )

        if "appearance" in by_category:
            recommendations.append(
                "Maintain consistent formatting: use standard section dividers, "
                "avoid excessive blank lines, capitalize headings."
            )

        # General recommendations
        recommendations.append(
            "Test the wizard with non-technical users to identify unclear "
            "prompts or confusing workflows."
        )

        return recommendations


def main():
    """Main test execution"""
    # Path to wizard script
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    wizard_path = os.path.join(repo_root, "platform-bootstrap", "setup-scripts", "platform-setup-wizard.sh")

    if not os.path.exists(wizard_path):
        print(f"ERROR: Wizard not found at {wizard_path}")
        sys.exit(1)

    tester = WizardUXTester(wizard_path)

    # Define test scenarios
    scenarios = [
        TestScenario(
            name="All Defaults (Minimal Setup)",
            description="Answer 'N' to all optional services, use all defaults",
            interactions=[
                (r"Press Enter to continue", ""),  # Initial banner
                (r"Press Enter to continue", ""),  # After environment detection
                (r"Enable OpenMetadata\?", "n"),
                (r"Enable Kerberos\?", "n"),
                (r"Enable Pagila\?", "n"),
                (r"Exit setup\?", "y"),  # Exit since no services selected
            ]
        ),
        TestScenario(
            name="Custom Values (Full Setup)",
            description="Enable all services, configure corporate infrastructure",
            interactions=[
                (r"Press Enter to continue", ""),  # Initial banner
                (r"Press Enter to continue", ""),  # After environment detection
                (r"Enable OpenMetadata\?", "y"),
                (r"Enable Kerberos\?", "y"),
                (r"Enable Pagila\?", "y"),
                (r"Configure corporate infrastructure\?", "y"),
                (r"Are your images prebuilt with all dependencies\?", "y"),
                (r"Enable password-less PostgreSQL", "y"),
                # Note: Would need to handle actual image config prompts in real scenario
                # For UX testing, we mainly care about the prompts themselves
            ]
        ),
        TestScenario(
            name="Validation Error Recovery",
            description="Select no services, then recover by re-selecting",
            interactions=[
                (r"Press Enter to continue", ""),  # Initial banner
                (r"Press Enter to continue", ""),  # After environment detection
                (r"Enable OpenMetadata\?", "n"),
                (r"Enable Kerberos\?", "n"),
                (r"Enable Pagila\?", "n"),
                (r"Exit setup\?", "n"),  # Don't exit, go back
                # Should re-prompt for services
                (r"Enable OpenMetadata\?", "y"),
                (r"Enable Kerberos\?", "n"),
                (r"Enable Pagila\?", "n"),
                (r"Configure corporate infrastructure\?", "n"),
                (r"Enable password-less PostgreSQL", "n"),
            ]
        ),
    ]

    # Run each scenario
    for scenario in scenarios:
        tester.scenarios.append(scenario)
        if tester.run_scenario(scenario):
            tester.analyze_ux_quality(scenario)

            # Print captured output sample
            print(f"\n  Output sample (first 500 chars):")
            print("  " + "-"*70)
            print(scenario.captured_output[:500].replace('\n', '\n  '))
            print("  " + "-"*70)

    # Generate and print report
    report = tester.generate_report()
    print(report)

    # Write report to file
    report_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "WIZARD_UX_QUALITY_REPORT.md"
    )
    with open(report_path, 'w') as f:
        f.write(report)

    print(f"\n\nReport written to: {report_path}")

    # Return exit code based on grades
    failing_grades = ['D', 'F', 'D+']
    has_failures = any(s.grade in failing_grades for s in tester.scenarios)

    return 1 if has_failures else 0


if __name__ == '__main__':
    sys.exit(main())
