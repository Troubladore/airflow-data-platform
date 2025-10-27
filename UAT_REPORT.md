# User Acceptance Testing Report
## Interactive Wizard - Business Analyst Perspective

**Date:** 2025-10-26
**Tester Role:** Business Analyst (Non-Technical User)
**Test Environment:** `/home/troubladore/repos/airflow-data-platform/.worktrees/data-driven-wizard`

---

## Executive Summary

The interactive wizard has **critical bugs** that prevent it from functioning correctly. The wizard stops prematurely after collecting only 3 inputs instead of completing the full flow. This makes it unusable for end-users.

**Status:** ❌ **FAILS ACCEPTANCE TESTING**

---

## Test Scenarios Executed

### ✅ Scenario 1: Setup Wizard - All Defaults

**Test:**
```bash
./platform setup
# Press Enter for every prompt (accept all defaults)
```

**Expected Behavior:**
- Wizard should collect all configuration values
- Default values should be shown in [brackets]
- Wizard should complete successfully with all services configured

**Actual Behavior:**
❌ **CRITICAL FAILURE:**
- Wizard stops after only 3 prompts (image, prebuilt, auth)
- Never asks for password or port
- State values stored as empty strings instead of defaults
- Configuration incomplete and unusable

**Detailed Findings:**

1. **Prompts shown (3 of 5 expected):**
   - ✅ PostgreSQL image: Shows prompt with default `[postgres:17.5-alpine]`
   - ✅ Prebuilt image: Shows prompt with default `[False]`
   - ✅ Auth method: Shows prompt with default `[md5]`
   - ❌ Password: NEVER SHOWN (missing)
   - ❌ Port: NEVER SHOWN (missing)

2. **State after execution:**
   ```
   services.postgres.image: ''           ← Empty string, not default!
   services.postgres.prebuilt: False     ← Correct
   services.postgres.auth_method: ''     ← Empty string, not 'md5'!
   services.postgres.password: MISSING
   services.postgres.port: MISSING
   ```

3. **Root Cause Analysis:**
   - When user presses Enter (empty string), interactive mode doesn't apply defaults
   - Empty string stored in state as-is
   - Conditional navigation `when_value` expects actual values (md5, trust, etc.)
   - Lookup for '' fails → returns None → wizard stops

**Impact:** 🔴 **CRITICAL - Wizard completely unusable with defaults**

---

### ✅ Scenario 2: Clean-Slate Wizard - Empty System

**Test:**
```bash
./platform clean-slate
```

**Expected Behavior:**
- Show discovery results
- Display clear "system is clean" message
- Explain what was checked
- Exit gracefully

**Actual Behavior:**
✅ **WORKS CORRECTLY**

**Positive Findings:**

1. ✅ Discovery phase clearly shown:
   ```
   Discovering platform services...

   Discovery complete. Found 0 total artifacts.
   ```

2. ✅ Clean message is clear and informative:
   ```
   System is already clean! No platform artifacts detected.

   Checked:
     - Docker containers
     - Docker images
     - Docker volumes
     - Configuration files
   ```

3. ✅ Exit is graceful (no errors, no prompts)

**UX Notes:**
- Message formatting is good
- Information is clear even for non-technical users
- No confusing jargon

---

### ✅ Scenario 3: Setup Wizard - Custom Values

**Test:**
```bash
./platform setup
# Enter custom values:
# - PostgreSQL image: postgres:16
# - Prebuilt: y
# - Auth: trust
# - Port: 5433
```

**Expected Behavior:**
- Accept custom values typed by user
- Validate inputs (reject invalid values)
- Skip password prompt for 'trust' auth
- Complete with custom configuration

**Actual Behavior:**
✅ **WORKS FOR EXPLICIT VALUES** (when user types actual values)

**Positive Findings:**

1. ✅ Custom values accepted and stored correctly:
   - Image: postgres:16 ✓
   - Prebuilt: True ✓
   - Auth method: trust ✓
   - Port: 5433 ✓

2. ✅ Conditional flow works correctly:
   - Password prompt correctly skipped for 'trust' auth
   - Proper branching based on auth_method value

3. ✅ All 4 prompts shown and processed

**UX Notes:**
- Works as expected when user types explicit values
- The bug only affects empty inputs (pressing Enter)

---

### ❌ Scenario 4: Validation - Invalid then Valid Input

**Test:**
```bash
./platform setup
# Enter invalid port: 99999
# Then valid port: 5432
```

**Expected Behavior:**
- Show clear error message for invalid port
- Re-prompt for port
- Accept valid port after error
- Continue with setup

**Actual Behavior:**
❌ **VALIDATION NOT TESTED** (wizard stopped before reaching port prompt)

**Findings:**
- Cannot test validation because wizard stops at auth_method
- Port prompt never reached in default flow
- Need to fix default handling first before testing validation

---

## Critical Issues (Must Fix)

### 🔴 Issue #1: Empty Input Doesn't Apply Defaults

**Severity:** CRITICAL
**Impact:** Wizard unusable for users who press Enter to accept defaults

**Problem:**
- In interactive mode, when user presses Enter (empty input), defaults are NOT applied
- Empty string stored in state instead of default value
- Breaks conditional navigation that expects actual values

**Technical Details:**
```python
# In _get_validated_input(), lines 85-91:
# Interactive mode branch DOESN'T handle empty string → default substitution
user_input = self.runner.get_input(step.prompt, default)
# If user presses Enter, get_input returns empty string ''
# This '' gets stored in state, NOT the default value
```

**Expected Fix:**
After getting input in interactive mode, check if empty and apply default:
```python
user_input = self.runner.get_input(step.prompt, default)
# If empty string and we have a default, use it
if user_input == '' and default is not None:
    user_input = default
```

**Test Case:**
```python
runner.input_queue = ['', '', '', '', '']  # All defaults
engine.execute_flow('setup')
# Should complete successfully with all defaults applied
```

---

### 🔴 Issue #2: Conditional Navigation Breaks on Empty Values

**Severity:** CRITICAL
**Impact:** Wizard stops mid-flow when state contains empty strings

**Problem:**
- `when_value` navigation expects specific keys (md5, trust, scram-sha-256)
- When empty string '' is in state, lookup fails
- Returns None → wizard stops

**Technical Details:**
```yaml
# In postgres/spec.yaml:
next:
  when_value:
    md5: postgres_password
    trust: postgres_port
    scram-sha-256: postgres_password
```

```python
# In _resolve_next(), line 216:
if new_value in value_map:
    return value_map[new_value]
return None  # Empty string not in map → returns None → stops
```

**Expected Behavior:**
Either:
1. Never store empty strings (always apply defaults), OR
2. Have fallback in when_value navigation

**Test Case:**
```python
# State: services.postgres.auth_method = ''
# Next: {when_value: {md5: password, trust: port}}
# Current: Returns None (bug)
# Expected: Either apply default 'md5' OR have fallback step
```

---

## Nice-to-Have Improvements

### 📋 Issue #3: Prompt Formatting Could Be Clearer

**Severity:** LOW
**Impact:** Minor UX polish

**Observation:**
Current prompt shows:
```
PostgreSQL image [{current_value}]:
```

The `{current_value}` placeholder is NOT being interpolated. Should either:
1. Show actual current value from state, OR
2. Show default value directly, OR
3. Remove placeholder entirely

**Suggested Improvement:**
```
PostgreSQL image (default: postgres:17.5-alpine):
```

Or better yet, follow the get_input pattern:
```
PostgreSQL image [postgres:17.5-alpine]:
```

---

### 📋 Issue #4: Enum Prompts Don't Show Options

**Severity:** MEDIUM
**Impact:** User doesn't know what values are valid

**Observation:**
Auth method prompt shows:
```
PostgreSQL authentication method:
```

User has NO IDEA what options are available!

**Suggested Improvement:**
```
PostgreSQL authentication method:
  1. md5 - MD5 password authentication (default)
  2. trust - Trust (no password)
  3. scram-sha-256 - SCRAM-SHA-256 (most secure)
Enter choice [1]:
```

---

### 📋 Issue #5: Boolean Prompts Use Technical Values

**Severity:** LOW
**Impact:** Minor confusion

**Observation:**
```
Use prebuilt image? (y/n): [False]
```

Showing `[False]` is technical. Better:
```
Use prebuilt image? (y/n) [n]:
```

---

## What Works Well

### ✅ Positive UX Aspects

1. **Clean-slate wizard is excellent:**
   - Clear discovery messaging
   - Helpful explanation of what was checked
   - Graceful exit for clean systems
   - Good formatting and readability

2. **Conditional logic works (when values are explicit):**
   - Password correctly skipped for 'trust' auth
   - Branching based on auth_method works perfectly
   - when_changed/when_unchanged logic functions correctly

3. **Custom values accepted properly:**
   - User can type explicit values
   - Values stored correctly in state
   - Type conversion works (boolean, integer)

4. **Display messages are clear:**
   - No technical jargon
   - Good use of whitespace
   - Readable for non-technical users

---

## Recommendations

### Immediate Actions (Before Next Test)

1. **Fix default handling in interactive mode:**
   - Apply defaults when user presses Enter (empty input)
   - Test with all-defaults scenario
   - Verify state contains actual default values, not empty strings

2. **Fix conditional navigation:**
   - Handle empty/missing values in when_value lookups
   - Add fallback navigation or default case
   - OR ensure defaults always applied (preferred)

3. **Test validation loop:**
   - Once port prompt is reachable, test validation
   - Verify error messages shown
   - Verify re-prompting works
   - Test invalid → valid flow

### Future Enhancements

4. **Improve enum prompts:**
   - Show numbered options
   - Let user enter number or value
   - Make defaults clearer

5. **Polish prompt formatting:**
   - Fix {current_value} interpolation
   - Consistent [bracket] format for defaults
   - Better boolean display (y/n instead of True/False)

6. **Add progress indicators:**
   - Show "Step 1 of 5" or similar
   - Help user know how much is left
   - Reduce anxiety about long wizards

---

## Test Evidence

### Scenario 1 Execution Trace

```
>>> Executing service: postgres
    Total steps: 8

    [1] Step: postgres_image (type: string)
        Old value: None
        New value:                          ← Empty string stored!
        State[services.postgres.image] =
        Next resolved: postgres_prebuilt

    [2] Step: postgres_prebuilt (type: boolean)
        Old value: None
        New value: False                    ← Boolean converted correctly
        State[services.postgres.prebuilt] = False
        Next resolved: postgres_auth

    [3] Step: postgres_auth (type: enum)
        Old value: None
        New value:                          ← Empty string stored!
        State[services.postgres.auth_method] =
        Next resolved: None                 ← FAILS HERE - no next step!

    Execution complete. Total steps executed: 3
```

### Scenario 3 Execution Trace (Custom Values)

```
Final State:
  services.postgres.image: postgres:16        ← Explicit value stored
  services.postgres.prebuilt: True            ← Boolean converted
  services.postgres.auth_method: trust        ← Explicit value stored
  services.postgres.port: 5433                ← Integer converted

Prompts shown: 4
Password prompt: SKIPPED (correct for trust auth)
```

---

## Conclusion

**The wizard is NOT ready for user acceptance.** While the architecture and design are sound, critical bugs prevent basic functionality:

1. ❌ **Cannot use defaults** - wizard stops after 3 prompts
2. ❌ **Configuration incomplete** - missing password and port
3. ✅ Works correctly when users type explicit values
4. ✅ Clean-slate wizard works perfectly

**Blocking Issues:**
- Issue #1: Empty input doesn't apply defaults (CRITICAL)
- Issue #2: Conditional navigation breaks on empty values (CRITICAL)

**Recommendation:** **DO NOT MERGE** until Issues #1 and #2 are fixed and tested.

---

## Next Steps

1. Developer fixes Issues #1 and #2
2. Re-run UAT with all scenarios
3. Test validation error handling (Scenario 4)
4. Verify end-to-end flow completes successfully
5. Consider polish improvements (Issues #3-5)

---

**Tested by:** Claude (Business Analyst Role)
**Test Date:** 2025-10-26
**Wizard Version:** setup.yaml v1.0, engine.py (current)
**Test Method:** Automated simulation with MockActionRunner
