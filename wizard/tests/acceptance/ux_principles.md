# UX Principles for Platform Setup Wizard

## Overview

This document defines UX standards for terminal-based wizard interfaces. These principles ensure users have a clear, professional, and frustration-free experience when setting up the data platform.

## Core Principles

### 1. Simplicity First
- **One question at a time**: Users should never feel overwhelmed
- **Sensible defaults**: Most users should be able to press Enter repeatedly
- **Progressive disclosure**: Advanced options only when needed
- **No cognitive overload**: Each prompt should be self-explanatory

### 2. Visual Clarity
- **Clean spacing**: Prompts separated by newlines, never run together
- **Consistent formatting**: All prompts follow the same pattern
- **Readable output**: No text collisions, overlaps, or garbled output
- **Professional appearance**: Output looks polished, not hacked together

### 3. Prompt Formatting Standards

#### Boolean Prompts
```
Install OpenMetadata? [y/N]:
```
- Format: `Question? [y/N]: ` or `Question? [Y/n]: `
- Capital letter indicates default
- Space after colon
- Each prompt on its own line

#### String Prompts with Defaults
```
PostgreSQL image [postgres:17.5-alpine]:
```
- Format: `Question [default_value]: `
- Default value clearly shown in brackets
- No {placeholders} - always interpolate variables
- Space after colon

#### String Prompts without Defaults
```
Custom image name:
```
- Format: `Question: `
- No brackets when no default
- Space after colon

### 4. Variable Interpolation
- **NEVER show {placeholders}**: Always interpolate before display
- **Current values visible**: Users see actual values, not template syntax
- **Context preserved**: Prompts reflect current state

### 5. Output Consistency

#### Box Formatting
```
╔════════════════════════════════════════════════════════╗
║           Service Configuration Complete               ║
╚════════════════════════════════════════════════════════╝
```
- Box width: 56 characters (consistent across all services)
- Top and bottom borders match exactly
- Text centered within box
- UTF-8 box drawing characters

#### Section Spacing
- One blank line between prompts
- Two blank lines between major sections
- Boxes separated from surrounding text by blank lines

### 6. No Duplicate Output
- **Each prompt shown EXACTLY once**: Never display the same prompt twice
- **No echo duplication**: User input shouldn't cause prompt re-display
- **Clean progression**: Linear flow from question to question

### 7. Error Handling
- **Clear error messages**: Explain what went wrong and how to fix it
- **Validation feedback**: Immediate feedback on invalid input
- **Recovery paths**: Users can correct mistakes without restarting

### 8. Color and Symbol Usage

#### Status Indicators
- ✓ (green): Success, completion
- ✗ (red): Error, failure
- ⚠ (yellow): Warning, caution
- ℹ (blue): Information, note

#### Consistent Color Scheme
- **Success**: Green text for confirmations
- **Errors**: Red text for failures
- **Warnings**: Yellow/orange for cautions
- **Prompts**: White/default for questions
- **Values**: Cyan for user inputs and defaults

### 9. Service-Specific Patterns

#### Multi-Service Wizards
When configuring multiple services (PostgreSQL, Airflow, etc.):
- **Consistent format across services**: Same box width, same prompt style
- **Clear service headers**: Each service clearly labeled
- **Parallel structure**: Same question types formatted identically

#### Configuration Summaries
```
PostgreSQL Configuration:
  - Image: postgres:17.5-alpine
  - Port: 5432
  - Auth: password
```
- Bullet points for lists
- Indentation for hierarchy
- Key-value pairs clearly separated

### 10. User Experience Quality

#### What Good UX Feels Like
Users should think:
- "This is professional and polished"
- "I understand what it's asking"
- "The defaults make sense"
- "This is fast and easy"

#### What Bad UX Feels Like
Users should NEVER think:
- "Why is everything repeated?"
- "What does {current_value} mean?"
- "This looks broken"
- "I'm confused about what to enter"

## Testing Criteria

### Manual Testing Checklist
When evaluating terminal output, verify:

- [ ] Each prompt appears exactly once
- [ ] Boolean prompts show [y/N] or [Y/n] format
- [ ] String prompts show [actual_value] not [{placeholder}]
- [ ] Clean newlines between all prompts
- [ ] No text running together on same line
- [ ] Box borders aligned and match (56 chars)
- [ ] Consistent spacing between sections
- [ ] Colors used appropriately
- [ ] Symbols display correctly (UTF-8)
- [ ] Professional overall appearance

### Automated Testing Approach

1. **Real Command Execution**: Run actual ./platform commands via subprocess
2. **Output Capture**: Capture stdout/stderr as users see it
3. **Pattern Matching**: Check for specific formatting issues
4. **LLM Evaluation**: Use AI to evaluate overall UX quality like a human would
5. **Grade Assignment**: A (excellent) to F (broken)

## Common Anti-Patterns to Avoid

### ❌ Duplicate Prompts
```
Install OpenMetadata?
Install OpenMetadata?:
```
**Why it's bad**: Looks broken, confuses users, wastes screen space

### ❌ Literal Placeholders
```
PostgreSQL image [{current_value}]:
```
**Why it's bad**: Users see template syntax instead of actual values

### ❌ Wrong Boolean Format
```
Install Kerberos? [False]:
```
**Why it's bad**: Technical jargon instead of user-friendly y/N format

### ❌ Run-Together Text
```
Install OpenMetadata?: Install Kerberos?: PostgreSQL image:
```
**Why it's bad**: Completely illegible, users can't read individual questions

### ❌ Inconsistent Box Width
```
╔════════════════╗        ╔════════════════════════════════════╗
║   Service 1    ║        ║          Service 2                ║
╚════════════════╝        ╚════════════════════════════════════╝
```
**Why it's bad**: Looks unprofessional, breaks visual consistency

## Success Metrics

### Grade A: Excellent
- Zero formatting issues
- Perfect consistency
- Users would describe as "polished" and "professional"
- Could show in a product demo

### Grade B: Good
- Minor cosmetic issues that don't affect usability
- Mostly consistent formatting
- Users can complete tasks without confusion

### Grade C: Acceptable
- Some formatting problems but functional
- Occasional inconsistencies
- Users might notice rough edges but can proceed

### Grade D: Poor
- Multiple formatting issues
- Inconsistent patterns
- Users notice problems and feel uncertain

### Grade F: Broken
- Duplicate prompts, run-together text
- Placeholder variables shown literally
- Users can't understand what's being asked

## Implementation Notes

### For Developers
- Read prompts from YAML with {placeholders}
- Interpolate variables BEFORE displaying to user
- Display prompt only ONCE (not in display() and get_input())
- Format boolean defaults as y/N in get_input(), not in YAML
- Test with real subprocess, capture actual output
- Use LLM agents to evaluate UX quality

### For Reviewers
- Run actual commands and look at terminal output
- Check against this document's criteria
- Use LLM evaluation for semantic quality assessment
- Don't approve PRs with broken terminal output
- UX testing is MANDATORY, not optional

## Acceptance Testing Methodology

### The Expect-Observe-Evaluate Pattern

**Before taking any action, ask:**
> "What do I expect to happen when I take the next action?"

**After the action completes, observe:**
> "Is that what actually happened? Is that better or worse than I expected?"

**Evaluation stance:**
- **Be mildly critical** - Don't let slop through
- **Be pragmatic** - Perfect is the enemy of the good
- **Focus on user impact** - Does this work for real users?

### Acceptance Test Structure

Each acceptance test should:
1. **State expectation** - What should happen (in comments or docstring)
2. **Execute action** - Run the actual wizard command with pexpect
3. **Observe results** - Capture what actually happened
4. **Evaluate** - Compare actual vs expected, assess quality
5. **Report** - PASS/FAIL with specific evidence

### Example Test Flow

```python
def test_clean_slate_removes_containers():
    """
    Expectation: Clean-slate should remove all platform containers.
    """
    # Take action
    child = pexpect.spawn('./platform clean-slate', timeout=60)
    # ... interact with prompts

    # Observe
    containers = subprocess.run(['docker', 'ps', '-a'], capture_output=True)

    # Evaluate
    assert 'platform-postgres' not in containers.stdout.decode()
    # Better: No containers, cleaner than having stopped ones
```

## Lesson Learned

We once had 448 passing unit tests but the wizard was completely broken in actual use. Why?

**Tests checked logic (state values) but never validated what users actually see.**

The fix: Permanent acceptance testing that runs real commands and evaluates terminal output quality with both pattern matching AND LLM evaluation.

**Never skip UX testing. It's how you catch the issues that matter to users.**
