# Security Guidelines

**🔒 Supply chain security for workstation automation**

## 🎯 Security Philosophy

This repository automates significant workstation configuration changes across Windows and WSL2. We follow security-first practices to minimize supply chain risks.

## ⚖️ Trust Model

**This repository operates on a "trust but verify" model:**

### Who Should Review This Code
- **Developers/Maintainers**: Use scanning tools during development
- **Security Teams**: Independent review before organizational deployment
- **Advanced Users**: Technical evaluation before personal use

### What End Users Should Do
- **DO**: Trust your organization's security review process
- **DO**: Run in test environments first
- **DON'T**: Assume included scanning tools "certify" safety
- **DON'T**: Skip organizational security approval processes

The included security scanner **identifies risks for human evaluation** - it does not provide automated security approval.

### 🎯 **Risk Acceptance Framework**
Not every security finding needs to be "fixed" - some risks are acceptable with proper justification:
- **Documentation examples**: Testing commands not executed in automation
- **Development tools**: Trusted sources with alternative validation
- **False positives**: Scanner limitations creating noise

See [Security Risk Acceptance Framework](docs/SECURITY-RISK-ACCEPTANCE.md) for complete guidance on documenting accepted risks.

## 🚨 Known Supply Chain Vectors

### Automation Dependencies
- **Ansible modules**: `pipx inject ansible-core pywinrm`
- **Python packages**: Dynamic installations via pip/pipx
- **Ansible Galaxy**: Community roles and collections
- **Shell downloads**: `curl | bash` patterns (now replaced with secure binary downloads)
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
# Secure binary download pattern (replaces curl | bash)
ASTRO_URL=$(curl -s https://api.github.com/repos/astronomer/astro-cli/releases/latest | grep "browser_download_url.*linux_amd64.tar.gz" | cut -d '"' -f 4)
wget -O /tmp/astro-cli.tar.gz "$ASTRO_URL"
# TODO: Add checksum verification
echo "expected_sha256_hash /tmp/astro-cli.tar.gz" | sha256sum -c
sudo tar -xzf /tmp/astro-cli.tar.gz -C /usr/local/bin --strip-components=0 astro
```

### 3. Minimal Privilege Approach
- WSL2 operations run as regular user where possible
- Windows operations attempt non-admin first
- Admin operations clearly marked and justified

## 🔍 Security Scanning Integration

### Developer/Maintainer Use
The included `./scripts/scan-supply-chain.sh` is designed for:
- **Code review processes** - Identify risks during development
- **Pre-commit validation** - Catch issues before they enter the repo
- **Security team evaluation** - Independent analysis before organizational approval

**Important**: This scanner does NOT certify code as "safe" - it surfaces risks for human evaluation.

### Pre-commit Hooks (For Developers)
```bash
# Install security scanning tools with pinned versions
pip install safety==3.2.9 ruff==0.7.4 semgrep==1.55.2

# Run before commits
safety check
ruff check .  # Fast linting + security checks
semgrep --config=auto .
./scripts/scan-supply-chain.sh  # Custom supply chain analysis
```

### CI/CD Integration (For Repository Maintainers)
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

### End User Considerations
**End users should NOT rely solely on this scanner for security decisions.**

Instead, consider:
- **Organizational security review** of the entire repository
- **Third-party security audit** for critical environments
- **Staged deployment** (test environments first)
- **Regular security updates** following your organization's policies

## 📋 Security Checklist

### Before Adding New Dependencies
- [ ] Is the source/maintainer trusted?
- [ ] Can we pin to specific versions?
- [ ] Can we verify checksums/signatures?
- [ ] Is it necessary or can we avoid the dependency?

### For Shell Commands
- [ ] Use secure binary downloads instead of `curl | bash` patterns
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
