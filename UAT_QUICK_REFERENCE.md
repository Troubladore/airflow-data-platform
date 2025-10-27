# UAT Quick Reference Card

## Status: ⚠️ Test Infrastructure Bug

---

## The Problem

❌ **Automated tests fail** - wizard stops after 3 prompts
✅ **Production likely works** - RealActionRunner has correct logic

---

## The Cause

**MockActionRunner returns empty string as-is:**
```python
return self.input_queue.pop(0)  # Returns ''
```

**RealActionRunner applies defaults:**
```python
return response if response else default  # Returns 'postgres:17.5-alpine'
```

---

## The Fix

**File:** `wizard/engine/runner.py` (line 144)

**Add 2 lines:**
```python
if self.input_queue:
    response = self.input_queue.pop(0)
    # NEW: Match RealActionRunner behavior
    return response if response else (default if default else '')
```

---

## Verification

1. Apply fix above
2. Run: `uv run python test_runner_parity.py`
3. Should see: "✅ PASS - 3/3 cases match"
4. Run: `uv run python test_uat.py`
5. Should see: "SUCCESS: Wizard completed with all defaults"

---

## Manual Test

```bash
./platform setup
# Press Enter 5 times
# Should see all prompts and complete successfully
```

---

## What Else Works

✅ Clean-slate wizard (perfect UX)
✅ Custom value input (works great)
✅ Conditional flow (logic solid)

---

## Optional Improvements

🟡 Show enum options to users
🟡 Display `[n]` instead of `[False]`
🟡 Fix `{current_value}` placeholder

---

## Recommendation

✅ **Fix mock** → ⏱️ 5 min
✅ **Manual test** → ⏱️ 5 min
✅ **Merge** → ⏱️ Ready!

---

## Files

- `UAT_EXECUTIVE_SUMMARY.md` - Read this first
- `UAT_FINAL_REPORT.md` - Complete analysis
- `test_runner_parity.py` - Verify fix works
