# UAT Summary: Interactive Wizard

## Overall Status: ❌ FAILS ACCEPTANCE

---

## Critical Bugs Found

### 🔴 Bug #1: Wizard Stops After 3 Prompts
**When:** User presses Enter to accept defaults
**What happens:**
```
✓ Prompt 1: PostgreSQL image → User presses Enter → Stores ''
✓ Prompt 2: Prebuilt → User presses Enter → Stores False (works!)
✓ Prompt 3: Auth method → User presses Enter → Stores ''
✗ STOPS HERE - Never asks for password or port
```

**Why it fails:**
- Empty string `''` stored instead of default value `'md5'`
- Conditional navigation looks for `'md5'` or `'trust'` in when_value map
- Lookup for `''` fails → returns None → wizard stops

**Impact:** 🔴 CRITICAL - Basic "press Enter to continue" flow broken

---

### 🔴 Bug #2: Defaults Not Applied in Interactive Mode
**Root cause:** Code in `_get_validated_input()` doesn't substitute defaults for empty strings in interactive mode

**Current code (lines 85-91):**
```python
# Interactive branch
default = step.default_value
user_input = self.runner.get_input(step.prompt, default)
# If user_input is '', it stays as ''
# Default is NOT substituted!
```

**Expected code:**
```python
user_input = self.runner.get_input(step.prompt, default)
if user_input == '' and default is not None:
    user_input = default  # Apply default for empty input
```

**Impact:** 🔴 CRITICAL - State contains empty strings instead of usable values

---

## Test Results

| Scenario | Status | Notes |
|----------|--------|-------|
| 1. All Defaults | ❌ FAIL | Stops after 3 prompts, state incomplete |
| 2. Clean-Slate | ✅ PASS | Works perfectly, good UX |
| 3. Custom Values | ✅ PASS | Works when user types explicit values |
| 4. Validation | ⏸️ BLOCKED | Cannot test - wizard stops before port prompt |

---

## What Works

✅ **Clean-slate wizard:**
- Discovery messaging clear
- "System is clean" message helpful
- Good formatting and flow

✅ **Custom value input:**
- Accepts typed values correctly
- Type conversion works (boolean, integer)
- Conditional flow correct (e.g., skips password for trust)

✅ **Display messages:**
- Clear, non-technical language
- Good use of whitespace
- Readable formatting

---

## What's Broken

❌ **Default handling:**
- Pressing Enter doesn't apply defaults
- Empty strings stored in state
- Wizard stops mid-flow

❌ **Navigation:**
- when_value lookups fail for empty strings
- No fallback case
- Abrupt termination

---

## User Experience Issues

### Critical (Blocks Users)
1. Cannot complete wizard using defaults
2. Configuration left incomplete
3. No error message - just stops

### Medium (Confusing)
4. Enum prompts don't show options
   ```
   Current:  PostgreSQL authentication method:
   Expected: PostgreSQL authentication method:
               1. md5 - MD5 password authentication
               2. trust - Trust (no password)
               3. scram-sha-256 - SCRAM-SHA-256
   ```

### Low (Polish)
5. `{current_value}` placeholder not interpolated
6. Boolean defaults show `[False]` instead of `[n]`

---

## Recommendation

**DO NOT MERGE** until critical bugs fixed.

### Must Fix (Blocking):
1. Apply defaults for empty input in interactive mode
2. Test all-defaults scenario completes successfully
3. Verify state contains actual values, not empty strings

### Should Fix (Important):
4. Show enum options to user
5. Test validation error handling
6. Add error message if wizard stops unexpectedly

### Nice to Have (Polish):
7. Fix prompt formatting
8. Improve boolean display
9. Add progress indicators

---

## Evidence

**State after "all defaults" scenario:**
```
services.postgres.image: ''              ← Should be 'postgres:17.5-alpine'
services.postgres.prebuilt: False        ← Correct
services.postgres.auth_method: ''        ← Should be 'md5'
services.postgres.password: MISSING      ← Never collected
services.postgres.port: MISSING          ← Never collected
```

**Expected state:**
```
services.postgres.image: 'postgres:17.5-alpine'
services.postgres.prebuilt: False
services.postgres.auth_method: 'md5'
services.postgres.password: 'changeme'
services.postgres.port: 5432
```

---

## Next Steps

1. Developer fixes default handling
2. Re-run UAT
3. Test validation loop
4. Verify end-to-end completion
5. Polish UX (optional)

---

**For non-technical users:** This wizard asks you questions to set up your database. Right now, if you just press Enter to use the recommended settings, it stops working halfway through. You must type out every value manually, which is frustrating and error-prone.

**For developers:** The interactive branch of `_get_validated_input()` doesn't substitute defaults for empty strings. Fix at line 91 by checking `if user_input == '' and default is not None: user_input = default`.
