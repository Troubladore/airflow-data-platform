# UX Design Principles - Platform Wizard

**Purpose:** Record design decisions and user feedback to guide consistent UX across all wizards
**Last Updated:** 2025-10-27

## Core Principles

### 1. Positive Phrasing (Feedback: 2025-10-27 01:50)

**Rule:** Always phrase questions in positive voice, never negative

**Bad:**
- "Skip image removal?"
- "Don't remove volumes?"
- "Avoid deleting data?"

**Good:**
- "Remove images?"
- "Remove volumes?"
- "Delete data?"

**Reason:** Humans process positive statements more easily. Double negatives are confusing.

---

### 2. Destructiveness Hierarchy (Feedback: 2025-10-27 01:50)

**Rule:** Order questions from least to most destructive

**Correct Order:**
1. Remove containers (can recreate instantly)
2. Remove images (can re-pull from registry)
3. Remove cloned folders/repos (can re-clone)
4. Remove data/databases (CANNOT RECOVER - most destructive)
5. Remove configuration (prevents recreation)

**Example - Pagila:**
```
Remove Pagila? [y/N]: y

  Pagila Removal Options

Remove cloned repository folder? [y/N]:
Remove database and data (cannot be recovered)? [y/N]:
Remove from platform configuration (prevents recreation on next setup)? [y/N]:
```

**Reason:** Let users make reversible choices first, save irreversible (data loss) for last.

---

### 3. Implied Actions (Feedback: 2025-10-27 01:55)

**Rule:** When user says "Remove [Service]", minimum implied actions happen automatically without asking

**Minimum Actions for "Remove Service":**
- Stop container (if running)
- Remove container

**These are NOT separate questions** - they're the bare minimum to "remove" something.

**THEN ask about optional destructive actions:**
- Remove images?
- Remove data?
- Remove config?

**Bad:**
```
Remove PostgreSQL? [y/N]: y
Stop container? [y/N]:          ← NO! Implied by "remove"
Remove container? [y/N]:        ← NO! Implied by "remove"
Remove images? [y/N]:           ← YES! Optional extra
```

**Good:**
```
Remove PostgreSQL? [y/N]: y
  (Container will be stopped and removed)
Remove Docker images? [y/N]:    ← Optional
Remove data volumes? [y/N]:     ← Optional
```

**Reason:** Don't ask permission for actions that are inherent to the choice already made.

---

### 4. Clear Terminology (Feedback: 2025-10-27 01:50, 01:58)

**Rule:** Be specific about what's being removed, avoid vague terms

**Bad:**
- "Remove Pagila components?"
- "Clean up Pagila?"
- "Remove repository?"

**Good:**
- "Remove Pagila?"
- "Remove cloned repository folder?"
- "Remove from platform configuration?"

**Specific clarifications needed:**
- "repository" → "cloned repository folder" (it's a folder on disk)
- "data" → "database and data"
- "config" → "platform configuration" with explanation of impact

**Reason:** Users need to know exactly what physical things will be deleted.

---

### 5. Explain Consequences (Feedback: 2025-10-27 01:58)

**Rule:** Tell users what removing config means for their workflow

**Bad:**
- "Remove configuration? [y/N]:"

**Good:**
- "Remove from platform configuration (prevents recreation on next setup)? [y/N]:"

**Reason:** "Remove configuration" is abstract. "Prevents recreation on next setup" is concrete and actionable.

---

### 6. Visual Hierarchy (Feedback: 2025-10-27 01:50)

**Rule:** Use section headers to separate high-level choices from detailed options

**Pattern:**
```
[High-level service selection]
Remove PostgreSQL? [y/N]: y
Remove Kerberos? [y/N]: n
Remove Pagila? [y/N]: y

────────────────────────────────────────────────────────
  PostgreSQL Removal Options
────────────────────────────────────────────────────────

[Detailed questions about what to remove]
Remove Docker images? [y/N]:
Remove data volumes (data will be lost)? [y/N]:

────────────────────────────────────────────────────────
  Pagila Removal Options
────────────────────────────────────────────────────────

Remove cloned repository folder? [y/N]:
...
```

**Reason:** Clear visual separation prevents confusion about "which service am I configuring now?"

---

### 7. No Redundant Questions (Feedback: 2025-10-27 02:00)

**Rule:** Don't ask the same thing twice with different words

**Bad:**
```
Tear down Pagila? [y/N]: y
Remove Pagila sample database? [y/N]:  ← Redundant! Pagila IS the sample database
```

**Good:**
```
Remove Pagila? [y/N]: y
  (Pagila is a sample database for PostgreSQL)

[Then specific removal options]
```

**Reason:** Redundant questions waste time and create doubt ("Wait, are these different things?")

---

### 8. Stop vs Clean-Slate (Feedback: 2025-10-27 01:55)

**Rule:** Stopping services (non-destructive) is separate from clean-slate (destructive)

**Stop/Shutdown:**
- Stops containers
- Services can be restarted
- No data loss
- Command: `make shutdown` or `make stop`

**Clean-Slate:**
- Removes containers (destructive)
- Optionally removes images, data, config
- Cannot simply "restart"
- Command: `make clean-slate`

**Reason:** Users need reversible "pause" option vs irreversible "remove" option.

---

## Application to Current Wizards

### Setup Wizard
- ✅ Uses [y/N] format
- ✅ Clear service names (OpenMetadata, Kerberos, Pagila)
- ✅ Simplified auth question ("Require password?" not "md5/trust/scram")
- ✅ Section headers between services
- ⚠️ Could add spacing between prompts (UX polish)

### Clean-Slate Wizard
- ✅ Discovery shows what exists first
- ✅ Asks which services to remove (high-level)
- ✅ Section headers for each service's detailed options
- ✅ Destructiveness hierarchy: images → repo → data → config
- ✅ Clear consequences ("prevents recreation on next setup")
- ✅ Positive phrasing ("Remove X?" not "Skip X?")

---

## Examples From User Feedback

### Feedback 1: Negative Phrasing
**Date:** 2025-10-27 01:50
**Issue:** "Skip image removal (Pagila has no images)? (y/n):"
**Problem:** Negative phrasing + user doesn't care if Pagila has images
**Fix:** Just don't ask the question if service has no images
**Applied:** Removed the question entirely

### Feedback 2: Unclear "Repository"
**Date:** 2025-10-27 01:50
**Issue:** "Remove Pagila repository?"
**Problem:** Is this the GitHub repo or local folder?
**Fix:** "Remove cloned repository folder?"
**Applied:** All teardown specs updated

### Feedback 3: "Tear Down" vs "Remove"
**Date:** 2025-10-27 02:00
**Issue:** "Tear down Pagila sample database?" then "Remove Pagila sample database?"
**Problem:** Same question asked twice with synonyms
**Fix:** Single question "Remove Pagila?" then detailed options
**Applied:** Pagila teardown spec simplified

### Feedback 4: Stop is Implied
**Date:** 2025-10-27 01:55
**Issue:** Asking "Stop container?" after "Remove service?"
**Problem:** Stopping is inherent to removing - don't ask separately
**Fix:** Stop+remove happen automatically, only ask about optional extras
**Applied:** Removed separate stop prompts

### Feedback 5: Explain Config Removal
**Date:** 2025-10-27 01:58
**Issue:** "Remove configuration?" - what does this mean?
**Problem:** Users don't know what config removal does to their workflow
**Fix:** "Remove from platform configuration (prevents recreation on next setup)?"
**Applied:** All config removal questions now explain impact

---

## Testing Validation

Every UX change must be validated with:
1. **pexpect tests** - Real terminal interaction simulation
2. **LLM UX evaluation** - Grade A/B required
3. **User feedback** - Manual testing by real users

**UX Testing is Mandatory** - See docs/CLAUDE.md

---

## Future Considerations

**Potential additions based on patterns:**
- Progress indicators for long operations (downloading, building)
- Confirmation summaries ("You selected to remove: X, Y, Z. Continue?")
- Undo/rollback for accidental deletions
- Dry-run mode ("Show what would be removed without doing it")

---

**This document is living - update as new UX feedback emerges.**
