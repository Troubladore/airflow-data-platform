# User Guide: Selecting Services During Setup

This guide explains how to choose which services to install when running the platform setup wizard.

---

## What You'll See

During setup, the wizard will show you available services:

```
  - openmetadata: OpenMetadata - Data catalog
  - kerberos: Kerberos - Authentication
  - pagila: Pagila - Sample database

Select services to install (space-separated):
```

---

## How to Select Services

### Format: Space-Separated Names

Type the service names you want, **separated by spaces**:

```
openmetadata kerberos
```

This will install OpenMetadata and Kerberos (plus PostgreSQL, which is always included).

---

## Examples

### Install Just PostgreSQL (Minimal Setup)
**What to type:** Press Enter without typing anything
```
Select services to install (space-separated): [press Enter]
```
**Result:** Only PostgreSQL is installed

---

### Install One Additional Service
**What to type:** Service name
```
Select services to install (space-separated): pagila
```
**Result:** PostgreSQL + Pagila

---

### Install Multiple Services
**What to type:** Service names separated by spaces
```
Select services to install (space-separated): openmetadata kerberos pagila
```
**Result:** PostgreSQL + OpenMetadata + Kerberos + Pagila

---

### Install Everything
**What to type:** All service names
```
Select services to install (space-separated): openmetadata kerberos pagila
```
**Result:** All available services

---

## Important Tips

### ✓ DO:
- Use **lowercase** service names: `openmetadata` not `OpenMetadata`
- Separate with **spaces**: `openmetadata kerberos`
- Copy names exactly as shown in the list
- Refer to the displayed options for correct spelling

### ✗ DON'T:
- Use commas: ~~`openmetadata,kerberos`~~ (won't work)
- Use mixed case: ~~`OpenMetadata`~~ (won't work)
- Add extra punctuation: ~~`openmetadata; kerberos`~~ (won't work)

---

## Available Services

### openmetadata
**What it is:** Data catalog and metadata management platform
**Use when:** You need to catalog and document your data assets
**Dependencies:** Requires PostgreSQL (automatically included)

### kerberos
**What it is:** Enterprise authentication system
**Use when:** You need secure authentication for your data platform
**Dependencies:** None

### pagila
**What it is:** Sample database with realistic data
**Use when:** You want to test the platform with example data
**Dependencies:** Requires PostgreSQL (automatically included)

---

## PostgreSQL (Always Included)

PostgreSQL is the core database and is **always installed**, even if you don't select any other services. You don't need to type "postgres" in your selection.

---

## What Happens Next

After you select services, the wizard will:

1. Configure each selected service
2. Ask service-specific questions (database passwords, ports, etc.)
3. Install and start the services
4. Show confirmation when complete

**Note:** Services you don't select will be skipped entirely. You can always re-run the wizard to add more services later.

---

## Troubleshooting

### "I made a typo and the service wasn't installed"

**Problem:** You typed `openmedata` instead of `openmetadata`

**What happens:** The wizard completes but that service isn't installed

**Solution:** Re-run the setup wizard and type the service name correctly

**Tip:** Copy/paste service names from the displayed list to avoid typos

---

### "I used commas and nothing was installed"

**Problem:** You typed `openmetadata,kerberos` (with commas)

**What happens:** Parser doesn't recognize comma-separated format

**Solution:** Re-run the wizard and use spaces instead: `openmetadata kerberos`

---

### "I don't see the service I selected"

**Checklist:**
1. Did you use lowercase? (`openmetadata` not `OpenMetadata`)
2. Did you use spaces? (not commas or semicolons)
3. Did you spell it exactly as shown in the list?

If you answered "no" to any of these, re-run the wizard with the correct format.

---

## Quick Reference Card

```
╔══════════════════════════════════════════════════════════╗
║         QUICK REFERENCE: Service Selection              ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Available Services:                                     ║
║    - openmetadata  (Data catalog)                        ║
║    - kerberos      (Authentication)                      ║
║    - pagila        (Sample database)                     ║
║                                                          ║
║  Format:                                                 ║
║    service1 service2 service3                            ║
║    (lowercase, space-separated, no commas)               ║
║                                                          ║
║  Examples:                                               ║
║    openmetadata                    (one service)         ║
║    openmetadata kerberos          (two services)         ║
║    openmetadata kerberos pagila   (all services)         ║
║    [press Enter]                   (postgres only)       ║
║                                                          ║
║  Notes:                                                  ║
║    • PostgreSQL is always included                       ║
║    • Services can be added later by re-running wizard    ║
║    • Copy service names to avoid typos                   ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

---

## Need Help?

If you're unsure which services to install:

- **Start minimal:** Just press Enter (PostgreSQL only)
- **Test first:** You can always re-run the wizard to add more services
- **All-in-one:** Type all three service names to get everything

The wizard is designed to be safe - you can run it multiple times without breaking your installation.
