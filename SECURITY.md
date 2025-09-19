# Security Guidelines

**🔒 Supply chain security for workstation automation**

## 🎯 Security Philosophy

This repository automates significant workstation configuration changes across Windows and WSL2. We follow security-first practices to minimize supply chain risks.

## 🚨 Known Supply Chain Vectors

### Automation Dependencies
- **Ansible modules**: `pipx inject ansible-core pywinrm`
- **Python packages**: Dynamic installations via pip/pipx
- **Ansible Galaxy**: Community roles and collections
- **Shell downloads**: `curl | bash` patterns
- **Windows packages**: Scoop, Chocolatey, direct downloads

### Runtime Risks
- **Certificate generation**: mkcert binary trust
- **Docker images**: Base image supply chain
- **PowerShell modules**: Windows package sources

## 🛡️ Current Mitigations

### 1. Explicit Version Pinning
```yaml
# All major dependencies are pinned
traefik_version: "v3.0"
registry_version: "2"
```

### 2. Checksum Verification
```bash
# Astro CLI installation (example of secure pattern)
curl -sSL install.astronomer.io | sudo bash -s
# TODO: Add checksum verification
```

### 3. Minimal Privilege Approach
- WSL2 operations run as regular user where possible
- Windows operations attempt non-admin first
- Admin operations clearly marked and justified

## 🔍 Security Scanning Integration

### Pre-commit Hooks
```bash
# Install security scanning
pip install safety bandit semgrep

# Run before commits
safety check
bandit -r ansible/
semgrep --config=auto .
```

### CI/CD Integration
```yaml
# .github/workflows/security.yml
- name: Supply Chain Security Scan
  run: |
    # Scan for unpinned dependencies
    ./scripts/scan-supply-chain.sh

    # Check Ansible playbooks
    ansible-lint ansible/

    # Python security scan
    safety check -r ansible/requirements.txt
```

## 📋 Security Checklist

### Before Adding New Dependencies
- [ ] Is the source/maintainer trusted?
- [ ] Can we pin to specific versions?
- [ ] Can we verify checksums/signatures?
- [ ] Is it necessary or can we avoid the dependency?

### For Shell Commands
- [ ] Avoid `curl | bash` patterns where possible
- [ ] Use package managers over direct downloads
- [ ] Verify signatures when available
- [ ] Document security assumptions

### For Ansible Tasks
- [ ] Minimize use of `shell:` and `command:` modules
- [ ] Use specific Ansible modules over shell commands
- [ ] Validate input parameters
- [ ] Use `no_log: true` for sensitive data

## 🚀 Recommended Improvements

### Short Term
1. **Pin Python dependencies**:
   ```bash
   # Create ansible/requirements.txt with pinned versions
   pywinrm==0.4.3
   ansible-core==2.16.1
   ```

2. **Add checksum verification**:
   ```bash
   # For critical downloads like Astro CLI
   wget -O astro.tar.gz https://releases.astronomer.io/...
   echo "expected_hash astro.tar.gz" | sha256sum -c
   ```

3. **Implement scanning script**:
   ```bash
   ./scripts/scan-supply-chain.sh
   ```

### Medium Term
1. **Container-based execution**:
   - Run Ansible from container with fixed dependencies
   - Eliminate host Python environment variations

2. **Signature verification**:
   - Verify GPG signatures where available
   - Implement organizational signing for custom components

3. **Network restrictions**:
   - Document network requirements
   - Consider air-gapped installation options

### Long Term
1. **Private package mirrors**:
   - Host vetted packages internally
   - Control update cadence

2. **Software Bill of Materials (SBOM)**:
   - Generate complete dependency manifests
   - Track all installed components

## 🆘 Incident Response

### If Compromise Suspected
1. **Isolate the workstation**
2. **Review recent automation runs**
3. **Check for unauthorized changes**:
   ```bash
   # Review Ansible logs
   journalctl -u ansible

   # Check for unexpected processes/services
   systemctl list-units --failed
   docker ps -a
   ```

4. **Rebuild from clean state**:
   ```bash
   ./scripts/teardown.sh  # Full cleanup
   # Fresh OS installation if needed
   ```

## 📞 Reporting Security Issues

**Do not** open public issues for security vulnerabilities.

Contact: [security contact information]

---

*Security is everyone's responsibility. When in doubt, ask questions and verify before executing.*