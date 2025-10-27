# UX Issues and Recommended Fixes

## Issue #1: Missing [y/N] Format (8 instances)

### Current (Line ~206 in platform-setup-wizard.sh)
```bash
echo "Does your organization use corporate infrastructure?"
echo ""
echo "Artifactory / Internal Registries"
echo "  • Internal Docker registry (artifactory.company.com)"
echo "  • Internal PyPI mirror"
echo "  • Internal git servers (for pagila, examples, etc.)"
echo ""
```

**Problem:** User doesn't know:
- That this is a yes/no question
- What the default is
- That they can press Enter to skip

### Fixed
```bash
echo "Artifactory / Internal Registries"
echo "  • Internal Docker registry (artifactory.company.com)"
echo "  • Internal PyPI mirror"
echo "  • Internal git servers (for pagila, examples, etc.)"
echo ""
if ask_yes_no "Configure corporate infrastructure?"; then
    NEED_ARTIFACTORY=true
    print_success "Corporate infrastructure: ENABLED"
```

**What changed:**
- Uses `ask_yes_no()` function which adds [y/N] automatically
- Clearer prompt: "Configure" instead of "Does your organization use"
- Default is now obvious (N is capitalized in [y/N])

---

## Issue #2: Unexplained Jargon - OpenMetadata

### Current (Line ~128 in platform-setup-wizard.sh)
```bash
echo "OpenMetadata - Metadata Catalog & Data Discovery"
echo "  • Catalog databases (PostgreSQL, SQL Server, etc.)"
echo "  • Track data lineage and quality"
echo "  • Collaborate on data documentation"
echo "  • Requirements: ~2GB RAM, Docker"
```

**Problem:**
- "OpenMetadata" is unexplained brand name
- "Metadata Catalog" is jargon explaining jargon
- What does it actually DO?

### Fixed
```bash
echo "OpenMetadata: Data Catalog Tool"
echo "  • Tracks what databases and tables you have"
echo "  • Shows how data flows between systems (lineage)"
echo "  • Central place for documentation"
echo "  • Requirements: ~2GB RAM, Docker"
echo ""
echo "  Think of it as: A search engine for your company's data"
```

**What changed:**
- Brief explanation: "Data Catalog Tool"
- Plain language bullets (no "catalog", "lineage", "collaborate")
- Added analogy: "search engine for data"

---

## Issue #3: Unexplained Jargon - Kerberos

### Current (Line ~149 in platform-setup-wizard.sh)
```bash
echo "Kerberos - SQL Server Authentication (Windows/Active Directory)"
echo "  • Connect to corporate SQL Server databases"
echo "  • Use your domain credentials (no passwords in code!)"
echo "  • Required: Domain membership, kinit access"
```

**Problem:**
- "Kerberos" is unexplained
- "kinit" is technical command
- "Domain membership" assumes Windows knowledge

### Fixed
```bash
echo "Kerberos: Secure Authentication for SQL Server"
echo "  • Connect to corporate databases using your Windows login"
echo "  • No need to store passwords in code"
echo "  • Required: Domain-joined computer, kinit command available"
echo ""
echo "  What it does: Lets Docker containers use your Windows credentials"
```

**What changed:**
- Explains what Kerberos does: "Secure Authentication"
- "kinit" is now "(kinit command)" or explained separately
- Added "What it does" section for clarity

---

## Issue #4: Unexplained Jargon - OLTP

### Current (Line ~99 in platform-setup-wizard.sh)
```bash
echo "Setting up platform infrastructure (always required)..."
echo "  • PostgreSQL: Shared OLTP for Airflow, OpenMetadata, etc."
echo "  • Network: platform_network for service communication"
```

**Problem:**
- "OLTP" is database jargon (Online Transaction Processing)
- "platform_network" sounds technical
- What does this infrastructure DO?

### Fixed
```bash
echo "Setting up core platform services (required for all features)..."
echo "  • PostgreSQL: Shared database for storing metadata"
echo "  • Docker Network: Allows services to communicate"
```

**What changed:**
- "OLTP" → "database for storing metadata"
- "platform_network" → "Docker Network"
- Added purpose: "Allows services to communicate"

---

## Issue #5: Unexplained Jargon - Artifactory

### Current (Line ~209 in platform-setup-wizard.sh)
```bash
echo "Artifactory / Internal Registries"
echo "  • Internal Docker registry (artifactory.company.com)"
echo "  • Internal PyPI mirror"
echo "  • Internal git servers (for pagila, examples, etc.)"
```

**Problem:**
- "Artifactory" brand name without explanation
- "PyPI" is Python jargon
- "Internal registries" - what are registries?

### Fixed
```bash
echo "Corporate Infrastructure: Custom Docker Images & Packages"
echo "  • Artifactory: Your company's Docker image repository"
echo "  • PyPI Mirror: Internal Python package server"
echo "  • Git Server: Internal repository for sample data"
echo ""
echo "  Why: Some companies block public Docker Hub / GitHub"
```

**What changed:**
- Headline explains the category
- Each tool has explanation
- Added "Why" section for context

---

## Issue #6: Progress Message Lacks Context

### Current (Line ~89 in platform-setup-wizard.sh)
```bash
echo "Creating platform-bootstrap/.env..."
```

**Problem:**
- Filename is technical (.env)
- What is this file for?
- Why is it being created?

### Fixed
```bash
echo "Creating platform configuration file (platform-bootstrap/.env)..."
echo "This file stores your service selections and image preferences."
```

**What changed:**
- Says what it is: "configuration file"
- Shows filename in parentheses
- Explains purpose in second line

---

## Issue #7: Progress Message Lacks Context

### Current (Line ~114 in platform-setup-wizard.sh)
```bash
echo "Starting services..."
```

**Problem:**
- Which services?
- How long will this take?

### Fixed
```bash
echo "Starting infrastructure services (PostgreSQL, Docker network)..."
echo "This may take 30-60 seconds on first run."
```

**What changed:**
- Specifies which services
- Sets time expectation
- More informative

---

## Implementation Checklist

### 🔴 Critical Fixes (2-3 hours)

- [ ] Add [y/N] format to all yes/no questions
  - [ ] Line ~206: "Configure corporate infrastructure? [y/N]"
  - [ ] Line ~214: Use ask_yes_no() for image mode question
  - [ ] Verify all echo prompts with yes/no use ask_yes_no()

- [ ] Explain jargon on first mention
  - [ ] Line ~128: OpenMetadata → "Data catalog tool"
  - [ ] Line ~149: Kerberos → "Secure authentication"
  - [ ] Line ~99: OLTP → "transactional database"
  - [ ] Line ~209: Artifactory → "Docker image repository"
  - [ ] Line ~35: kinit → "(Kerberos login command)"
  - [ ] Line ~457: OpenSearch → "Search engine"
  - [ ] Line ~82: PyPI → "(Python package repository)"

### 🟡 High Priority (1 hour)

- [ ] Add context to progress messages
  - [ ] Line ~89: "Creating platform-bootstrap/.env..." → Add purpose
  - [ ] Line ~114: "Starting services..." → Specify which services

- [ ] Add help text to welcome
  - [ ] Line ~48: Add note about [y/N] format
  - [ ] Add note about jargon explanations

### 🟢 Nice to Have (Optional)

- [ ] Add glossary reference at end
- [ ] Consider "Quick Start" mode
- [ ] Add visual indicators for optional vs required
- [ ] Capitalize all section headings consistently

---

## Testing Commands

After making changes, test with:

```bash
# Run UX quality test
python3 platform-bootstrap/tests/test-wizard-ux-manual.py

# Run the wizard manually
./platform-bootstrap/setup-scripts/platform-setup-wizard.sh

# Check for [y/N] format in all questions
grep -n "ask_yes_no\|read -p.*\?" platform-bootstrap/setup-scripts/platform-setup-wizard.sh
```

---

## Expected Grade Improvement

| Category | Before | After | Change |
|----------|--------|-------|--------|
| Prompts Clear | A (100) | A (100) | - |
| [y/N] Format | D- (60) | A (95) | +35 |
| Progress | A- (90) | A (95) | +5 |
| No Jargon | F (10) | B+ (85) | +75 |
| Appearance | A+ (99) | A+ (99) | - |
| **OVERALL** | **C (72)** | **A- (90)** | **+18** |

---

## Validation

After fixes, the wizard should:

✓ Show [y/N] on ALL yes/no questions
✓ Explain technical terms on first mention
✓ Provide context in progress messages
✓ Be understandable to non-technical users
✓ Still work perfectly for technical users

Test with both technical and non-technical users to verify.
