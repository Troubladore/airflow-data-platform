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

## Additional Resources

- [MIT Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)
- [Kerberos Wiki Debugging Guide](https://k5wiki.kerberos.org/wiki/Debugging)
- [Microsoft Kerberos Troubleshooting](https://docs.microsoft.com/en-us/windows-server/security/kerberos/)

---

*This guide is based on industry-standard practices and tools, adapted for the specific challenges of running Kerberos authentication in containerized environments.*
