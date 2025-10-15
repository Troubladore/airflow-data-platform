# Kerberos Diagnostics Guide for Docker + WSL2 + SQL Server

## Overview

This guide provides comprehensive diagnostics approaches for troubleshooting Kerberos authentication issues when running Docker containers in WSL2 that need to authenticate to a remote SQL Server using Kerberos ticket cache.

While you don't need to build everything from scratch, the complex environment (Docker + WSL2 + SQL Server + cross-platform) typically requires combining standard tools with custom instrumentation for effective troubleshooting.

## What to Observe and Diagnose

Before diving into tools, it's essential to understand what needs to be visible in your scenario:

### Key Diagnostic Areas

1. **Ticket Cache State**
   - Is your container seeing a valid TGT in the credential cache?
   - Does it see the right cache file (path, ownership, permissions)?

2. **Principal/Realm Configuration**
   - Which principal/realm is being used for authentication?

3. **Service Ticket Request/SPN Resolution**
   - What SPN is the SQL client requesting?
   - Is the KDC providing a ticket?

4. **KDC Communication**
   - DNS lookups for KDC discovery
   - Queries to the KDC (UDP/TCP port 88)
   - Error messages from the KDC

5. **Encryption Types**
   - Do the client and KDC agree on acceptable encryption types?

6. **Time Synchronization**
   - Are clocks synchronized within allowed skew?

7. **Network Connectivity**
   - Port reachability inside containers/WSL2 bridges
   - Firewall rules

8. **SQL Server Configuration**
   - SPN mismatches
   - Mutual authentication settings

## Standard Tools and Facilities

### Core Diagnostic Tools

| Tool/Mechanism | Purpose | Usage in Your Scenario |
|----------------|---------|------------------------|
| **KRB5_TRACE** | MIT Kerberos trace logging | Set `KRB5_TRACE=/dev/stdout` before launching binaries for extremely verbose internal library operations |
| **KDC Logs** | Server-side ticket request logs | Correlate client-side traces with KDC logs if you have AD/KDC access |
| **strace/ltrace** | System call tracing | Confirm file paths, DNS lookups, and network syscalls |
| **tcpdump/Wireshark** | Network packet capture | Capture KDC traffic, DNS queries, and Kerberos exchanges |
| **klist/kvno/kinit** | Kerberos CLI tools | View, request, and validate tickets |
| **krb5.conf [logging]** | Configuration-based logging | Enable moderate logging in client lib or KDC processes |

### Using KRB5_TRACE

```bash
# Enable trace logging to stdout
export KRB5_TRACE=/dev/stdout
kinit username@REALM

# Or to a file
export KRB5_TRACE=/path/to/trace.log
kvno MSSQLSvc/sqlserver.domain.com:1433
```

## Custom Instrumentation Requirements

Due to the containerized environment, you'll likely need additional "bridging" instrumentation:

### 1. Wrapper/Probe Container

Create a diagnostic sidecar container that:
- Shares the same pod/network namespace
- Can run diagnostic commands (klist, kvno, kinit with trace)
- Shares credential cache volume (read-only)
- Mounts the same `/etc/krb5.conf`

### 2. SQL Client/Library Instrumentation

- Enable verbose logging for GSSAPI/SPNEGO/Kerberos steps
- Wrap or intercept GSSAPI negotiation calls
- For Java/.NET, enable debug flags for Kerberos libraries

### 3. Log Aggregation

- Correlate timestamps across container, host, and KDC logs
- Add correlation IDs (container ID, principal)
- Use centralized logging for multi-source searching

### 4. Health Checks

At container startup:
- Run diagnostic checks (kinit → kvno to SQL SPN)
- Test GSSAPI handshake
- Monitor credential expiration

### 5. Debug Mode

Bundle a diagnostic mode that enables:
- Full trace logging
- Packet capture
- Credential cache dumps

## Practical Troubleshooting Approach

### Step 1: Validate Baseline from Host

On your WSL2 host (outside containers):

```bash
# Obtain ticket
kinit username@REALM

# Verify ticket
klist

# Test SQL SPN
kvno MSSQLSvc/sqlserver.domain.com:1433

# Enable tracing
KRB5_TRACE=/dev/stdout kvno MSSQLSvc/sqlserver.domain.com:1433

# Capture network traffic
sudo tcpdump -i any port 88 -w kerberos.pcap
```

### Step 2: Test in Minimal Container

Launch a basic container with same configuration:

```bash
docker run -it \
  -v /path/to/krb5.conf:/etc/krb5.conf:ro \
  -v /tmp/krb5cc_$(id -u):/tmp/krb5cc_1000:ro \
  --network=your-network \
  debian:latest bash

# Inside container
apt-get update && apt-get install -y krb5-user
KRB5_TRACE=/dev/stdout klist
kvno MSSQLSvc/sqlserver.domain.com:1433
```

### Step 3: Compare Environments

Check for differences in:
- Credential cache type (FILE vs KEYRING vs DIR)
- File permissions and UID/GID mapping
- DNS resolution and network routing
- SPN canonicalization

### Step 4: Enable SQL Driver Debugging

For different drivers:

```bash
# JDBC
-Dsun.security.krb5.debug=true

# ADO.NET
System.Diagnostics.Trace.Listeners.Add(new TextWriterTraceListener(Console.Out));

# ODBC
[ODBC]
Trace=Yes
TraceFile=/tmp/odbc.log
```

### Step 5: Cross-check KDC Logs

Review KDC logs for:
- Client IP/principal/time
- Error codes:
  - `KDC_ERR_ETYPE_NOSUPP`
  - `KDC_ERR_PREAUTH_FAILED`
  - `KDC_ERR_S_PRINCIPAL_UNKNOWN`

### Step 6: Iterate with Narrowed Scope

- If minimal container works but real container fails: compare library versions, security profiles
- If minimal container fails: focus on network, DNS, credential cache access

## Known Pitfalls in Docker + WSL2 + Kerberos

### Common Issues and Solutions

1. **Credential Cache Type/Kernel Support**
   - Modern krb5 uses `KEYRING:` or `DIR:` instead of `FILE:`
   - Container kernel may not support chosen type
   - Solution: Force `FILE:` cache type in krb5.conf

2. **Filesystem Permissions/UID Mapping**
   - Container may map UIDs differently
   - Solution: Check file ownership and permissions inside container

3. **DNS/SRV Lookup Differences**
   - Container DNS servers may differ from host
   - Solution: Verify DNS configuration and SRV records

4. **Network Isolation**
   - Docker/WSL bridging may block KDC ports
   - Solution: Check firewall rules and NAT configuration

5. **Time Synchronization**
   - Clock skew between container/host/KDC
   - Solution: Sync time or increase allowed skew in krb5.conf

6. **SPN Canonicalization**
   - Different hostname resolution in container
   - Solution: Use FQDN consistently

7. **Multiple Krb5 Libraries**
   - Conflicting versions between host/container/driver
   - Solution: Standardize on single krb5 version

8. **Delegation/Impersonation**
   - Missing delegation flags or S4U settings
   - Solution: Check delegation configuration

## Quick Diagnostics Checklist

- [ ] Can you get a TGT on the host? (`kinit`)
- [ ] Can you list tickets on the host? (`klist`)
- [ ] Can you get a service ticket for SQL SPN on the host? (`kvno`)
- [ ] Does the minimal container see the ticket cache?
- [ ] Can the minimal container reach the KDC? (port 88)
- [ ] Does DNS resolution work inside the container?
- [ ] Are container/host/KDC clocks synchronized?
- [ ] Is the correct credential cache type being used?
- [ ] Are file permissions correct for the cache file?
- [ ] Does the SQL driver request the correct SPN?

## Summary and Recommendations

### Key Takeaways

1. **Use standard tools first**: KRB5_TRACE, packet capture, KDC logs, and command-line tools provide excellent baseline diagnostics

2. **Custom glue needed**: In containerized environments, you'll need lightweight probes/wrappers/sidecars to bridge visibility gaps

3. **Incremental approach**: Start with known-working host environment, then minimal container, then real container

4. **Common failure points**: Focus on credential cache type, network isolation, DNS differences, and time sync

### Best Practices

- Always enable `KRB5_TRACE` when debugging
- Use tcpdump/Wireshark to verify network communication
- Create a diagnostic sidecar container for production debugging
- Implement startup health checks for early detection
- Maintain detailed logging with correlation IDs
- Document your specific environment's quirks

## Diagnostic Output Design: Human vs AI Agent Consumption

### The Paradigm Shift in Diagnostic Consumption

Modern diagnostic tools must serve two distinct but overlapping audiences:

1. **Human operators** who need readable, actionable information
2. **AI assistants** (ChatGPT, Claude) that help humans troubleshoot
3. **Future MCP agents** that will programmatically consume and act on diagnostics

### Design Principles for AI-Ready Diagnostics

#### 1. Self-Contained Context
Every diagnostic output should contain **complete grounding information** that allows an LLM or MCP agent to understand the situation without additional context:

```markdown
# Example Structure
## System Context
- Environment: WSL2/Docker/Kubernetes
- Purpose: Kerberos authentication for SQL Server
- Architecture: Sidecar pattern for ticket sharing

## Current State
- All relevant configuration
- Current status of all components
- Recent actions taken

## Problem Description
- What is failing
- When it started failing
- What changed recently

## Diagnostic Data
- Structured test results
- Error messages with full context
- Network/DNS/Time sync status
```

#### 2. Structured Output Formats

Provide multiple output modes to serve different consumers:

```bash
# Human-readable (default)
./diagnostic-tool.sh

# JSON for MCP agents and monitoring
./diagnostic-tool.sh --json > diagnostic.json

# Markdown for LLM consumption
./diagnostic-tool.sh --markdown > context.md
```

#### 3. Actionable Recommendations

Include specific, executable commands for remediation:

```json
{
  "issues": [
    {
      "id": "no_ticket",
      "severity": "critical",
      "description": "No valid Kerberos ticket found",
      "recommendation": {
        "action": "obtain_ticket",
        "command": "kinit username@REALM",
        "rationale": "Kerberos requires valid ticket for authentication"
      }
    }
  ]
}
```

#### 4. Progressive Disclosure

Structure output for both quick scanning and deep analysis:

```
=== SUMMARY ===
❌ Authentication failing: No valid Kerberos ticket

=== QUICK FIX ===
Run: kinit username@DOMAIN.COM

=== DETAILED ANALYSIS ===
[Full diagnostic data for LLM consumption]
```

### Implementation Patterns

#### Pattern 1: Diagnostic Context Generator
Create standalone scripts that generate complete diagnostic contexts:

```bash
# generate-diagnostic-context.sh
# Outputs a complete markdown file that can be pasted to ChatGPT/Claude
# Includes all system info, configurations, test results, and recommendations
```

#### Pattern 2: Logging with Dual Output
Setup wizards and long-running processes should:
- Display output to screen for human monitoring
- Save to timestamped log files for later analysis
- Maintain "latest" symlinks for easy access

```bash
# run-setup.sh | tee logs/setup-$(date +%Y%m%d-%H%M%S).log
# ln -sf $LOG_FILE logs/setup-latest.log
```

#### Pattern 3: Test Output Annotations
Include metadata that helps LLMs understand test significance:

```yaml
test_result:
  name: "SQL Server Kerberos Authentication"
  purpose: "Verify container can authenticate to SQL Server using shared Kerberos tickets"
  prerequisites:
    - "Valid Kerberos ticket"
    - "Network connectivity to SQL Server"
    - "Correct SPNs registered"
  result: "FAILED"
  error: "Cannot authenticate using Kerberos"
  likely_cause: "Missing or incorrect SPN registration"
  suggested_action: "Contact DBA to verify SPNs with: setspn -L <service_account>"
```

### Future MCP (Model Context Protocol) Considerations

As MCP adoption grows, our diagnostics should be ready:

1. **Semantic Structure**: Use consistent JSON schemas that MCP servers can interpret
2. **Tool Definitions**: Expose diagnostic functions as MCP tools
3. **State Management**: Provide stateful diagnostic sessions that agents can iterate on
4. **Correlation IDs**: Enable tracking across distributed systems

Example MCP-ready diagnostic:
```json
{
  "version": "1.0.0",
  "protocol": "mcp",
  "session_id": "diag-2024-10-15-001",
  "context": {
    "system": "kerberos-sidecar",
    "environment": "development",
    "correlation_id": "req-123456"
  },
  "capabilities": [
    "test_ticket_validity",
    "verify_network_connectivity",
    "check_spn_registration"
  ],
  "current_state": { ... },
  "available_actions": [ ... ]
}
```

### Best Practices for AI-Assisted Troubleshooting

1. **Always include timestamps** - LLMs need to know data freshness
2. **Explain acronyms on first use** - Not all LLMs have domain knowledge
3. **Include examples of working state** - Helps LLMs understand what "good" looks like
4. **Provide file paths and locations** - Enables specific guidance
5. **Version your diagnostic output** - Allows LLMs to handle format changes
6. **Test with actual LLMs** - Verify output is genuinely helpful

### Measuring Diagnostic Effectiveness

Track whether your diagnostics are AI-friendly:

- Can an LLM solve the issue with ONLY your diagnostic output?
- Does the output avoid ambiguity that confuses LLMs?
- Are recommendations specific and executable?
- Is the context complete without being overwhelming?

### Example: LLM-Optimized Error Message

Instead of:
```
Error: Authentication failed
```

Provide:
```
Error: Kerberos authentication to SQL Server failed
System: Container attempting to connect to sqlserver01.company.com:1433
Method: Using Kerberos ticket from shared cache at /krb5/cache/krb5cc
Ticket Status: Valid (expires 2024-10-15 18:00 UTC)
Network: Port 1433 reachable
Likely Cause: SQL Server SPN not registered or incorrect
Next Step: Run './check-sql-spn.sh sqlserver01.company.com' to verify SPN
If SPN missing: Ask DBA to run 'setspn -A MSSQLSvc/sqlserver01.company.com:1433 <service_account>'
```

## Additional Resources

- [MIT Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)
- [Kerberos Wiki Debugging Guide](https://k5wiki.kerberos.org/wiki/Debugging)
- [Microsoft Kerberos Troubleshooting](https://docs.microsoft.com/en-us/windows-server/security/kerberos/)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

---

*This guide is based on industry-standard practices and tools, adapted for the specific challenges of running Kerberos authentication in containerized environments, with forward-looking considerations for AI-assisted and automated troubleshooting.*
