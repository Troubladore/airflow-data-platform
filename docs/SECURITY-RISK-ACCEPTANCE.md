# Security Risk Acceptance Framework

**🛡️ Balancing security with productivity through documented risk acceptance**

## 🎯 Philosophy

Not every security finding needs to be "fixed" - some risks are acceptable based on:
- **Business context**: Development vs production environments
- **Risk vs effort**: High-effort fixes for low-risk issues
- **Trust boundaries**: Tools and sources we already trust
- **False positives**: Scanner limitations creating noise

## 📋 Risk Acceptance Process

### 1. **Identify Risk**
Security scanner flags an issue during development or CI/CD.

### 2. **Evaluate Risk**
Ask these questions:
- Is this a real security risk or scanner false positive?
- What's the actual impact if exploited?
- What's the effort to fix vs risk level?
- Do we trust the source/tool involved?
- Is this a development-only concern?

### 3. **Document Acceptance**
Add entry to `.security-exceptions.yml`:

```yaml
exceptions:
  - pattern: "your-specific-pattern"
    category: "risk_category"
    justification: |
      WHAT: Specific description of what was flagged
      WHY FLAGGED: Why the scanner identified this as a risk
      WHY ACCEPTED: Business/technical reason for accepting the risk
      RISK LEVEL: Assessment of actual risk (None/Low/Medium/High)
      CONTEXT: Additional context about when/where this occurs
      TECHNICAL_DEBT: Any follow-up work needed (optional)
    accepted_by: "Security Team"
    accepted_date: "2025-09-19"
    expires: "2026-03-19"  # Realistic future date
    review_frequency: "quarterly"
```

### 4. **Review and Approval**
- Risk must be approved by authorized team member
- Justification must be business-focused, not technical convenience
- Expiration date ensures periodic review

## 🗂️ Risk Categories

### **unpinned_dependencies**
**When to accept**: Documentation examples, development tools
```yaml
- pattern: "pip install safety ruff semgrep"
  justification: "Documentation example for security tools - not executed in automation"
```

### **dynamic_downloads**
**When to accept**: Testing commands, package installations via apt/yum
```yaml
- pattern: "curl -k https://registry.localhost"
  justification: "Validation testing command in docs - not executed during setup"
```

### **hardcoded_secrets**
**When to accept**: Configuration examples, false positives (file permissions, etc.)
```yaml
- pattern: "key.*0600"
  justification: "File permission documentation - not actual secrets"
```

### **docker_unpinned**
**When to accept**: Development examples, rapid iteration environments
```yaml
- pattern: "FROM python:3.11-slim"
  justification: "Development example - production uses pinned versions"
```

### **privilege_escalation**
**When to accept**: Legitimate system administration tasks
```yaml
- pattern: "become: yes.*Install system packages"
  justification: "Required for package installation - documented with admin comment"
```

## ✅ Best Practices

### **Good Justifications**
- ✅ "Development environment only - production uses different approach"
- ✅ "Documentation example - not executed in automation"
- ✅ "Trusted vendor binary - validated through other means"
- ✅ "False positive - scanner misidentifies configuration as secret"

### **Bad Justifications**
- ❌ "Too hard to fix right now"
- ❌ "It works fine"
- ❌ "Low priority"
- ❌ "Scanner is wrong" (without explanation)

### **Expiration Guidelines**
- **Development tools**: 1 year
- **Documentation examples**: 1 year
- **Temporary workarounds**: 3-6 months
- **Architecture decisions**: 2-3 years

### **Review Frequency**
- **quarterly**: Active development, changing requirements
- **annual**: Stable tools, established patterns
- **biennial**: Long-term architecture decisions

## 🔄 Exception Management

### **Adding New Exceptions**
```bash
# 1. Run scanner to identify issues
./scripts/scan-supply-chain.sh

# 2. Add exception to .security-exceptions.yml
# 3. Commit with justification in commit message
# 4. Get approval from authorized team member
```

### **Regular Reviews**
Scanner automatically warns about:
- **Expiring exceptions** (30 days before expiration)
- **Expired exceptions** (no longer honored)

### **Exception Updates**
```bash
# Update expiration date
expires: "2026-01-19"

# Change review frequency
review_frequency: "quarterly"

# Update justification
justification: "Updated business context explains continued acceptance"
```

## 📊 Monitoring and Reporting

### **Dashboard Visibility**
Track exception metrics:
- Total accepted risks by category
- Expiring exceptions requiring review
- New exceptions added per month
- Risk reduction over time

### **Audit Trail**
Every exception includes:
- Who accepted the risk
- When it was accepted
- Why it was accepted
- When it needs review
- Pattern that triggered the exception

## 🚨 Security Guardrails

### **Automatic Protections**
- Expired exceptions are no longer honored
- New exceptions require authorized approval
- Patterns must be specific (no wildcards for entire categories)
- All exceptions have mandatory expiration dates

### **Human Oversight**
- Security team reviews all new exceptions
- Regular audits of accepted risk patterns
- Business justification required for all acceptances
- Periodic assessment of risk vs productivity balance

## 💡 Example Scenarios

### **Scenario 1: Documentation Testing Commands**
```yaml
# Accept: curl commands used only for validation examples
- pattern: "curl -k https://.*localhost"
  category: "dynamic_downloads"
  justification: |
    WHAT: curl commands in validation documentation for testing registry connectivity
    WHY FLAGGED: Scanner detects curl as potential dynamic download security risk
    WHY ACCEPTED: These are manual testing commands in documentation - not automated execution
    RISK LEVEL: None - documentation examples only
    CONTEXT: Users run these commands manually to verify their setup works correctly
  accepted_by: "Security Team"
  accepted_date: "2025-09-19"
  expires: "2026-03-19"
```

### **Scenario 2: Development Container Flexibility**
```yaml
# Accept: Unpinned base images in development examples
- pattern: "FROM.*-slim$"
  category: "docker_unpinned"
  justification: "Development examples only - production uses specific versions"
  accepted_by: "DevOps Team"
  expires: "2025-07-19"
  review_frequency: "quarterly"
```

### **Scenario 3: Trusted Tool Installation**
```yaml
# Accept: Direct binary download from trusted vendor
- pattern: "install.astronomer.io"
  category: "dynamic_downloads"
  justification: "Official Astronomer installation - replaced with secure binary download method"
  accepted_by: "Platform Team"
  expires: "2025-06-19"
  review_frequency: "quarterly"
```

---

*This framework ensures security awareness while maintaining development velocity. Every accepted risk is conscious, documented, and subject to regular review.*
