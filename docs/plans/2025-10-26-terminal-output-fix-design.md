# Terminal Output Fix - Design Document

**Date:** 2025-10-26
**Status:** Approved for Implementation

## Problem Statement

The wizard terminal output is completely broken for actual users:

**Actual output from real run:**
```
Install OpenMetadata?
Install OpenMetadata?: Install Kerberos?
Install Kerberos?: Install Pagila?
Install Pagila?: PostgreSQL image [{current_value}]:
PostgreSQL image [{current_value}]: [postgres:17.5-alpine]:
```

**Critical issues:**
1. Every prompt shown TWICE (display + get_input duplicate)
2. Prompts run together on same line (no newlines)
3. Boolean defaults show `[False]` instead of `[y/N]`
4. Placeholders not interpolated (`{current_value}` shown literally)
5. Wizard crashes partway through

**Root cause:** All 448 tests use MockActionRunner and never validate actual terminal output. We tested logic (values in state) but not UX (what users see).

## Solution Overview

**Iterative fix strategy:**
- Fix one issue at a time
- Validate each fix with real subprocess terminal output
- Use LLM agent to evaluate UX quality
- Each fix gets its own commit

**Permanent infrastructure:**
- Create LLM-based acceptance test framework
- Document UX principles
- Make UX testing mandatory in code review
- Add to CLAUDE.md as permanent workflow

## Design Principles

1. **Real terminal validation** - Run actual commands via subprocess, not mocks
2. **LLM evaluation** - Agent evaluates output like a human user would
3. **Visual quality standards** - Alignment, spacing, colors, box borders
4. **Permanent infrastructure** - UX tests become standard test suite
5. **Parallel execution** - UX testing runs alongside code review (not after)

## Architecture

### Component 1: UX Principles Document

**File:** `wizard/tests/acceptance/ux_principles.md`

Defines standards for:
- Simplicity (one question at a time, simple inputs, clear defaults)
- Clarity (prompts shown once, proper newlines, no run-together)
- Feedback (progress shown, success clear)
- Visual Continuity (consistent formatting across services)
- Typography and Alignment (text aligned, indentation consistent)
- Spacing and Readability (blank lines, comfortable rhythm)
- Box Drawing (borders align, consistent widths)
- Color and Symbols (✓ ✗ ⚠ ℹ used consistently)
- Progressive Disclosure (don't overwhelm, group related questions)

**Specific formatting rules:**
- Boolean: `Question? [y/N]: ` (not `[False]`)
- String: `Field [default]: ` (with space before colon)
- Integer: `Port [5432]: ` (interpolated, not `{variable}`)
- Headers: 56-char borders with 2-space indent
- Sections: Use ──── for subsections, ════ for main headers

### Component 2: LLM Validation Framework

**File:** `wizard/tests/acceptance/llm_validator.py`

```python
def run_acceptance_test_agent(scenario_name, command, inputs, ux_principles_path):
    """Run wizard, capture output, dispatch LLM to evaluate.

    Returns:
        {
            'passed': bool,
            'overall_grade': 'A/B/C/D/F',
            'issues': [{severity, problem, quote, should_be, principle}],
            'positive_aspects': [str],
            'user_quote': str
        }
    """
    # 1. Run actual command via subprocess
    result = subprocess.run(command, input=inputs, capture_output=True, text=True, timeout=10)

    # 2. Load UX principles
    principles = read_file(ux_principles_path)

    # 3. Dispatch LLM agent to evaluate
    agent_prompt = f"""
    You are a UX expert evaluating CLI wizard output.

    SCENARIO: {scenario_name}

    ACTUAL OUTPUT:
    {result.stdout}

    UX PRINCIPLES:
    {principles}

    Evaluate EVERY aspect:
    - Is each prompt shown exactly once?
    - Are defaults formatted correctly ([y/N], [5432], not [False])?
    - Are variables interpolated (no {{placeholders}})?
    - Are box borders aligned (56 chars, matching top/bottom)?
    - Is spacing clean (blank lines between sections)?
    - Do prompts have proper newlines (not running together)?
    - Is visual style consistent across all services?
    - Would a non-technical user understand this?

    Return structured JSON with issues found.
    """

    # Use Task tool to dispatch agent
    evaluation = dispatch_agent(agent_prompt)

    return evaluation
```

### Component 3: Permanent Test Suite

**File:** `wizard/tests/acceptance/test_ux_validation.py`

```python
@pytest.mark.acceptance
class TestSetupWizardUX:
    """Permanent UX validation for setup wizard."""

    def test_all_defaults_ux(self):
        """Pressing Enter for all prompts should have excellent UX."""
        result = run_acceptance_test_agent(
            scenario_name="Setup - all defaults",
            command=['./platform', 'setup'],
            inputs='\n' * 8,
            ux_principles_path='wizard/tests/acceptance/ux_principles.md'
        )

        assert result['passed'], f"UX issues: {result['issues']}"
        assert result['overall_grade'] in ['A', 'B']

    def test_custom_values_ux(self):
        """Custom inputs should have excellent UX."""
        result = run_acceptance_test_agent(
            scenario_name="Setup - custom values",
            command=['./platform', 'setup'],
            inputs='y\nn\ny\npostgres:16\ny\ntrust\n\n5433\n',
            ux_principles_path='wizard/tests/acceptance/ux_principles.md'
        )

        assert result['passed'], f"UX issues: {result['issues']}"
```

**These tests run in CI on every PR.**

### Component 4: Developer Workflow (CLAUDE.md)

**Add to repository CLAUDE.md:**

```markdown
## 🎨 User Experience Testing - MANDATORY

**EVERY code review MUST include UX validation.**

### Parallel Review Pattern

When completing Task Xc (Review phase):

```
Launch 2 agents IN PARALLEL (single message, 2 Task calls):
1. superpowers:code-reviewer - Technical review
2. general-purpose agent - UX acceptance testing with REAL terminal output

Wait for both, apply ALL feedback.
```

### UX Test Requirements

UX tests MUST:
- ✅ Run REAL commands via subprocess
- ✅ Capture actual stdout/stderr
- ✅ LLM evaluates like a human user
- ✅ Check: prompts, formatting, spacing, alignment, colors, boxes
- ✅ Validate visual consistency

### Why This Matters

We once had 448 passing tests but the wizard was unusable because:
- Duplicate prompts
- Wrong formatting ([False] vs [y/N])
- Text running together

**Tests validated logic, not user experience.**

UX testing is now permanent infrastructure.
```

Does this complete design make sense for permanent UX testing infrastructure?