#!/usr/bin/env python3
"""
Manual Terminal UX Quality Test - Captures Full Wizard Output
==============================================================

Runs wizard scenarios and captures complete terminal output for manual review.
Provides detailed grading on specific UX criteria.
"""

import os
import sys
import subprocess
import re
from dataclasses import dataclass
from typing import List


@dataclass
class UXCriteria:
    """UX quality criteria with grading"""
    name: str
    weight: float  # Weight in final grade (0.0-1.0)
    score: float = 0.0  # Score 0-100
    issues: List[str] = None
    observations: List[str] = None

    def __post_init__(self):
        if self.issues is None:
            self.issues = []
        if self.observations is None:
            self.observations = []


class ManualUXGrader:
    """Manually grade wizard UX quality from captured output"""

    def __init__(self, output: str, scenario_name: str):
        self.output = output
        self.lines = output.split('\n')
        self.scenario_name = scenario_name
        self.criteria = self._init_criteria()

    def _init_criteria(self) -> List[UXCriteria]:
        """Initialize grading criteria"""
        return [
            UXCriteria("Prompts Clear", weight=0.25),
            UXCriteria("[y/N] Format Correct", weight=0.20),
            UXCriteria("Progress Messages Shown", weight=0.20),
            UXCriteria("No Jargon", weight=0.20),
            UXCriteria("Professional Appearance", weight=0.15),
        ]

    def grade(self) -> str:
        """Grade all criteria and return letter grade"""
        print(f"\n{'='*80}")
        print(f"Grading: {self.scenario_name}")
        print(f"{'='*80}\n")

        # Grade each criterion
        self._grade_prompts()
        self._grade_yn_format()
        self._grade_progress()
        self._grade_jargon()
        self._grade_appearance()

        # Calculate weighted final score
        final_score = sum(c.score * c.weight for c in self.criteria)

        # Convert to letter grade
        if final_score >= 95:
            grade = "A+"
        elif final_score >= 90:
            grade = "A"
        elif final_score >= 87:
            grade = "B+"
        elif final_score >= 83:
            grade = "B"
        elif final_score >= 80:
            grade = "B-"
        elif final_score >= 77:
            grade = "C+"
        elif final_score >= 73:
            grade = "C"
        elif final_score >= 70:
            grade = "C-"
        elif final_score >= 67:
            grade = "D+"
        elif final_score >= 63:
            grade = "D"
        elif final_score >= 60:
            grade = "D-"
        else:
            grade = "F"

        return grade, final_score

    def _grade_prompts(self):
        """Grade prompt clarity"""
        criterion = self.criteria[0]
        score = 100

        # Find all question lines
        questions = [
            (i, line) for i, line in enumerate(self.lines)
            if '?' in line and len(line.strip()) > 0
        ]

        criterion.observations.append(f"Found {len(questions)} questions")

        for i, line in questions:
            # Check for overly long prompts
            if len(line.strip()) > 100:
                criterion.issues.append(
                    f"Line {i}: Prompt too long ({len(line.strip())} chars)"
                )
                score -= 5

            # Check for unclear phrasing
            if re.search(r"not.*not|don't.*not", line, re.IGNORECASE):
                criterion.issues.append(
                    f"Line {i}: Double negative: {line.strip()[:60]}"
                )
                score -= 10

            # Check for missing context
            if len(line.strip()) < 20 and '?' in line:
                criterion.issues.append(
                    f"Line {i}: Question lacks context: {line.strip()}"
                )
                score -= 5

        # Check for "Press Enter" prompts - should be clear
        press_enter_lines = [
            line for line in self.lines
            if 'Press Enter' in line or 'press Enter' in line
        ]
        criterion.observations.append(
            f"Found {len(press_enter_lines)} 'Press Enter' prompts"
        )

        criterion.score = max(0, score)

    def _grade_yn_format(self):
        """Grade yes/no format consistency"""
        criterion = self.criteria[1]
        score = 100

        # Find yes/no questions
        yn_questions = []
        for i, line in enumerate(self.lines):
            if '?' in line and any(
                word in line.lower()
                for word in ['enable', 'configure', 'want', 'use', 'need', 'have']
            ):
                yn_questions.append((i, line))

        criterion.observations.append(f"Found {len(yn_questions)} yes/no questions")

        correct_format = 0
        missing_format = 0

        for i, line in yn_questions:
            # Check for [y/N] or [Y/n] format
            match = re.search(r'\[([yY])/([nN])\]', line)

            if match:
                correct_format += 1
                y, n = match.groups()

                # Check default is clear (one uppercase, one lowercase)
                if (y.isupper() and n.isupper()) or (y.islower() and n.islower()):
                    criterion.issues.append(
                        f"Line {i}: Unclear default - both same case: [{y}/{n}]"
                    )
                    score -= 8
            else:
                missing_format += 1
                criterion.issues.append(
                    f"Line {i}: Missing [y/N] format: {line.strip()[:60]}"
                )
                score -= 15

        if yn_questions:
            criterion.observations.append(
                f"{correct_format}/{len(yn_questions)} have correct format"
            )

        criterion.score = max(0, score)

    def _grade_progress(self):
        """Grade progress messaging"""
        criterion = self.criteria[2]
        score = 100

        # Look for progress indicators
        progress_patterns = [
            (r'detecting|checking', 'detection'),
            (r'setting up|configuring|creating', 'setup'),
            (r'starting|launching|loading', 'startup'),
            (r'complete|success|done|finished', 'completion'),
        ]

        found_categories = set()
        progress_lines = []

        for i, line in enumerate(self.lines):
            for pattern, category in progress_patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    found_categories.add(category)
                    progress_lines.append((i, line, category))

        criterion.observations.append(
            f"Found {len(progress_lines)} progress messages "
            f"across {len(found_categories)} categories"
        )

        # Should have messages in at least 2 categories
        if len(found_categories) < 2:
            criterion.issues.append(
                f"Insufficient progress categories ({len(found_categories)}/4)"
            )
            score -= 20

        # Check for progress without context
        for i, line, category in progress_lines:
            if len(line.strip().split()) < 3:
                criterion.issues.append(
                    f"Line {i}: Progress message too vague: {line.strip()}"
                )
                score -= 5

        # Should have reasonable number of progress messages
        if len(progress_lines) < 5:
            criterion.issues.append(
                f"Too few progress messages ({len(progress_lines)} found)"
            )
            score -= 15

        criterion.score = max(0, score)

    def _grade_jargon(self):
        """Grade jargon usage"""
        criterion = self.criteria[3]
        score = 100

        # Technical terms that should be explained
        jargon_terms = {
            'openmetadata': 'Metadata catalog',
            'opensearch': 'Search engine',
            'kerberos': 'Authentication',
            'artifactory': 'Artifact repository',
            'pypi': 'Python packages',
            'wsinterop': 'WSL integration',
            'kinit': 'Get Kerberos ticket',
            'klist': 'List tickets',
            'oltp': 'Transactional database',
        }

        jargon_found = []

        for i, line in enumerate(self.lines):
            for term, explanation in jargon_terms.items():
                if term in line.lower():
                    # Check if explanation is nearby (within 2 lines)
                    context_start = max(0, i - 2)
                    context_end = min(len(self.lines), i + 3)
                    context = ' '.join(
                        self.lines[context_start:context_end]
                    ).lower()

                    # Look for explanatory text nearby
                    has_explanation = (
                        explanation.lower() in context or
                        ' - ' in line or  # Dash explanation
                        '(' in line  # Parenthetical explanation
                    )

                    if not has_explanation:
                        jargon_found.append((i, term))
                        criterion.issues.append(
                            f"Line {i}: Unexplained jargon: '{term}'"
                        )
                        score -= 5

        criterion.observations.append(
            f"Found {len(jargon_found)} unexplained jargon terms"
        )

        criterion.score = max(0, score)

    def _grade_appearance(self):
        """Grade professional appearance"""
        criterion = self.criteria[4]
        score = 100

        # Check for excessive blank lines
        blank_count = 0
        max_blanks = 0

        for line in self.lines:
            if not line.strip():
                blank_count += 1
                max_blanks = max(max_blanks, blank_count)
            else:
                blank_count = 0

        if max_blanks > 4:
            criterion.issues.append(
                f"Excessive blank lines ({max_blanks} consecutive)"
            )
            score -= 10

        # Check for consistent section formatting
        section_markers = []
        for line in self.lines:
            stripped = line.strip()
            if stripped.startswith('===') or stripped.startswith('---'):
                section_markers.append(stripped[0])

        if len(set(section_markers)) > 2:
            criterion.issues.append("Inconsistent section dividers")
            score -= 8

        # Check for proper heading capitalization
        headings = [
            line for line in self.lines
            if line.strip().endswith(':') and len(line.strip().split()) <= 5
        ]

        for heading in headings:
            if heading.strip() and not heading.strip()[0].isupper():
                criterion.issues.append(
                    f"Heading not capitalized: {heading.strip()}"
                )
                score -= 3

        # Check for ANSI escape codes (should be clean with NO_COLOR)
        ansi_codes = re.findall(r'\x1b\[[0-9;]*m', self.output)
        if ansi_codes:
            # This is okay - means colors are being used
            criterion.observations.append("Contains color codes (acceptable)")
        else:
            criterion.observations.append("Plain ASCII output (NO_COLOR respected)")

        criterion.score = max(0, score)

    def print_report(self, grade: str, final_score: float):
        """Print detailed grading report"""
        print(f"\n{'='*80}")
        print(f"GRADE: {grade} ({final_score:.1f}/100)")
        print(f"{'='*80}\n")

        for criterion in self.criteria:
            print(f"\n{criterion.name}:")
            print(f"  Score: {criterion.score:.0f}/100 (weight: {criterion.weight*100:.0f}%)")
            print(f"  Contribution: {criterion.score * criterion.weight:.1f} points")

            if criterion.observations:
                print(f"\n  Observations:")
                for obs in criterion.observations:
                    print(f"    • {obs}")

            if criterion.issues:
                print(f"\n  Issues:")
                for issue in criterion.issues:
                    print(f"    ✗ {issue}")

        print(f"\n{'='*80}\n")


def run_scenario(scenario_name: str, inputs: List[str]) -> str:
    """Run wizard with simulated inputs"""
    print(f"\nRunning scenario: {scenario_name}")
    print(f"Inputs: {inputs}")

    wizard_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        "platform-bootstrap",
        "setup-scripts",
        "platform-setup-wizard.sh"
    )

    try:
        # Run wizard with input
        env = os.environ.copy()
        env['NO_COLOR'] = '1'  # Request plain output

        input_str = '\n'.join(inputs) + '\n'

        result = subprocess.run(
            ['bash', wizard_path],
            input=input_str,
            capture_output=True,
            text=True,
            timeout=30,
            env=env
        )

        output = result.stdout + result.stderr
        print(f"Captured {len(output)} characters")

        return output

    except subprocess.TimeoutExpired as e:
        print("Timeout - wizard may require Docker or other resources")
        return e.stdout.decode() if e.stdout else ""
    except Exception as e:
        print(f"Error: {e}")
        return ""


def main():
    """Main test execution"""
    print("="*80)
    print("MANUAL TERMINAL UX QUALITY TEST")
    print("="*80)

    scenarios = [
        {
            'name': 'Scenario 1: All Defaults (Exit Early)',
            'inputs': [
                '',  # Press Enter - welcome
                '',  # Press Enter - after detection
                'n',  # OpenMetadata
                'n',  # Kerberos
                'n',  # Pagila
                'y',  # Exit (since no services)
            ],
        },
        {
            'name': 'Scenario 2: Custom Values',
            'inputs': [
                '',  # Press Enter - welcome
                '',  # Press Enter - after detection
                'y',  # OpenMetadata
                'y',  # Kerberos
                'y',  # Pagila
                'y',  # Corporate infrastructure
                'y',  # Prebuilt images
                'y',  # Passwordless PostgreSQL
            ],
        },
        {
            'name': 'Scenario 3: Validation Recovery',
            'inputs': [
                '',  # Press Enter - welcome
                '',  # Press Enter - after detection
                'n',  # OpenMetadata
                'n',  # Kerberos
                'n',  # Pagila
                'n',  # Don't exit - go back
                'y',  # OpenMetadata
                'n',  # Kerberos
                'n',  # Pagila
                'n',  # Corporate
                'n',  # Passwordless
            ],
        },
    ]

    reports = []

    for scenario in scenarios:
        print(f"\n{'#'*80}")
        output = run_scenario(scenario['name'], scenario['inputs'])

        if output:
            # Save raw output
            output_file = f"/tmp/wizard_output_{len(reports)}.txt"
            with open(output_file, 'w') as f:
                f.write(output)
            print(f"Saved raw output to: {output_file}")

            # Grade the output
            grader = ManualUXGrader(output, scenario['name'])
            grade, score = grader.grade()
            grader.print_report(grade, score)

            reports.append({
                'name': scenario['name'],
                'grade': grade,
                'score': score,
                'grader': grader,
            })

    # Final summary
    print(f"\n{'='*80}")
    print("FINAL SUMMARY")
    print(f"{'='*80}\n")

    for report in reports:
        print(f"{report['name']}: {report['grade']} ({report['score']:.1f}/100)")

    # Overall recommendations
    print(f"\n{'='*80}")
    print("RECOMMENDATIONS")
    print(f"{'='*80}\n")

    all_issues = []
    for report in reports:
        for criterion in report['grader'].criteria:
            all_issues.extend(criterion.issues)

    # Categorize recommendations
    format_issues = [i for i in all_issues if '[y/N]' in i or 'format' in i.lower()]
    jargon_issues = [i for i in all_issues if 'jargon' in i.lower()]
    progress_issues = [i for i in all_issues if 'progress' in i.lower()]

    print("\n1. YES/NO FORMAT:")
    if format_issues:
        print("   - Ensure all yes/no questions use [y/N] with clear defaults")
        print(f"   - Found {len(format_issues)} format issues")
    else:
        print("   ✓ Format is consistent")

    print("\n2. JARGON:")
    if jargon_issues:
        print("   - Add explanations for technical terms")
        print(f"   - Found {len(jargon_issues)} unexplained terms")
    else:
        print("   ✓ Technical terms well explained")

    print("\n3. PROGRESS MESSAGES:")
    if progress_issues:
        print("   - Add more contextual progress updates")
        print(f"   - Found {len(progress_issues)} progress issues")
    else:
        print("   ✓ Progress messaging is adequate")

    print("\n4. OVERALL:")
    avg_score = sum(r['score'] for r in reports) / len(reports)
    if avg_score >= 80:
        print(f"   ✓ Good UX quality (avg: {avg_score:.1f}/100)")
    else:
        print(f"   ✗ UX needs improvement (avg: {avg_score:.1f}/100)")

    return 0


if __name__ == '__main__':
    sys.exit(main())
