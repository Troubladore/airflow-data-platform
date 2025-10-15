#!/bin/bash
# Generate comprehensive diagnostic context for LLM consumption
# Creates a self-contained diagnostic report that can be fed to ChatGPT/Claude
# Future-ready for MCP (Model Context Protocol) agent consumption

set -e

# Script version
VERSION="1.0.0"

# Output format (text or json)
OUTPUT_FORMAT="${1:-text}"
OUTPUT_FILE="${2:-diagnostic-context.md}"

# Timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HUMAN_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Color codes for terminal output (disabled for file output)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    CYAN=''
    NC=''
fi

echo -e "${CYAN}Generating comprehensive diagnostic context...${NC}"
echo ""

# Start building the diagnostic context
{
    echo "# Kerberos Authentication Diagnostic Context"
    echo ""
    echo "**Generated:** $HUMAN_TIME"
    echo "**Purpose:** Self-contained diagnostic information for troubleshooting Kerberos/SQL authentication issues"
    echo ""
    echo "---"
    echo ""
    echo "## 🤖 LLM Instructions"
    echo ""
    echo "This diagnostic report contains comprehensive information about a Kerberos authentication environment."
    echo "Use this information to help diagnose and resolve authentication issues with SQL Server or other Kerberized services."
    echo "All necessary context is included below - no additional information should be needed."
    echo ""
    echo "---"
    echo ""
    echo "## 📋 Environment Overview"
    echo ""
    echo "### System Information"
    echo "\`\`\`"
    echo "Hostname: $(hostname)"
    echo "OS: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"

    if [ -f /etc/os-release ]; then
        echo "Distribution: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    fi

    if grep -q Microsoft /proc/version 2>/dev/null; then
        echo "Environment: WSL2"
    elif [ -f /.dockerenv ]; then
        echo "Environment: Docker Container"
    else
        echo "Environment: Native Linux"
    fi

    echo "User: $(whoami)"
    echo "Groups: $(groups)"
    echo "\`\`\`"
    echo ""

    echo "### Docker Environment"
    echo "\`\`\`"
    if command -v docker >/dev/null 2>&1; then
        echo "Docker: $(docker --version)"
        echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'Not installed')"

        # Check for our sidecar
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q kerberos; then
            echo ""
            echo "Kerberos Sidecar Status:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep kerberos
        else
            echo "Kerberos Sidecar: Not running"
        fi
    else
        echo "Docker: Not installed"
    fi
    echo "\`\`\`"
    echo ""

    echo "## 🔑 Kerberos Configuration"
    echo ""

    echo "### Ticket Status"
    echo "\`\`\`"
    if [ -n "$KRB5CCNAME" ]; then
        echo "KRB5CCNAME: $KRB5CCNAME"
    else
        echo "KRB5CCNAME: Not set (using default)"
    fi
    echo ""

    if command -v klist >/dev/null 2>&1; then
        if klist -s 2>/dev/null; then
            echo "Ticket Status: VALID"
            echo ""
            klist 2>/dev/null
        else
            echo "Ticket Status: NO VALID TICKET"
            echo ""
            echo "Error output:"
            klist 2>&1 || true
        fi
    else
        echo "klist: Not installed (cannot check tickets)"
    fi
    echo "\`\`\`"
    echo ""

    echo "### Kerberos Configuration File"
    echo "\`\`\`"
    if [ -f /etc/krb5.conf ]; then
        echo "Location: /etc/krb5.conf"
        echo ""
        echo "Key settings:"
        grep -E '(default_realm|dns_lookup|ticket_lifetime|forwardable)' /etc/krb5.conf 2>/dev/null | grep -v '^#' | head -20
    else
        echo "No /etc/krb5.conf found"
    fi
    echo "\`\`\`"
    echo ""

    echo "## 🌐 Network Configuration"
    echo ""

    echo "### DNS Configuration"
    echo "\`\`\`"
    if [ -f /etc/resolv.conf ]; then
        echo "Nameservers:"
        grep nameserver /etc/resolv.conf | head -5
        echo ""
        echo "Search domains:"
        grep search /etc/resolv.conf || echo "None configured"
    fi
    echo "\`\`\`"
    echo ""

    echo "### Time Synchronization (Critical for Kerberos)"
    echo "\`\`\`"
    echo "Current time: $(date)"
    echo "UTC time: $(date -u)"
    echo ""

    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl status 2>/dev/null | grep -E '(Local time|Universal time|synchronized|NTP)' || echo "timedatectl not available"
    elif command -v ntpstat >/dev/null 2>&1; then
        ntpstat 2>/dev/null || echo "NTP not synchronized"
    else
        echo "No time sync tools found (timedatectl/ntpstat)"
    fi
    echo "\`\`\`"
    echo ""

    echo "## 🗄️ SQL Server Tools"
    echo ""
    echo "\`\`\`"

    # Check for sqlcmd
    if command -v sqlcmd >/dev/null 2>&1; then
        echo "sqlcmd: Found in PATH"
        sqlcmd -? 2>/dev/null | head -3
    elif [ -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
        echo "sqlcmd: Found at /opt/mssql-tools18/bin/sqlcmd"
        /opt/mssql-tools18/bin/sqlcmd -? 2>/dev/null | head -3
    elif [ -x "/opt/mssql-tools/bin/sqlcmd" ]; then
        echo "sqlcmd: Found at /opt/mssql-tools/bin/sqlcmd"
    else
        echo "sqlcmd: NOT INSTALLED"
        echo ""
        echo "Installation required for SQL Server testing"
    fi

    # Check for ODBC
    if [ -f /etc/odbcinst.ini ]; then
        echo ""
        echo "ODBC Drivers:"
        grep '\[' /etc/odbcinst.ini 2>/dev/null || echo "No drivers configured"
    fi
    echo "\`\`\`"
    echo ""

    echo "## 📊 Recent Diagnostic Tests"
    echo ""

    # Check for recent test results
    if [ -f diagnostic-results.json ]; then
        echo "### Last Test Results"
        echo "\`\`\`json"
        cat diagnostic-results.json 2>/dev/null || echo "No results available"
        echo "\`\`\`"
    else
        echo "No recent test results found."
        echo "Run './krb5-auth-test.sh -v' to generate detailed diagnostics."
    fi
    echo ""

    echo "## 🔍 Automated Analysis"
    echo ""

    # Perform automated checks and provide recommendations
    ISSUES_FOUND=false

    echo "### Issue Detection"
    echo ""

    # Check 1: Kerberos ticket
    if ! klist -s 2>/dev/null; then
        ISSUES_FOUND=true
        echo "❌ **No valid Kerberos ticket**"
        echo "   - Impact: Cannot authenticate to Kerberized services"
        echo "   - Resolution: Run \`kinit username@DOMAIN.COM\`"
        echo ""
    fi

    # Check 2: Time sync
    if command -v timedatectl >/dev/null 2>&1; then
        if ! timedatectl status 2>/dev/null | grep -q "synchronized: yes"; then
            ISSUES_FOUND=true
            echo "⚠️  **Time not synchronized**"
            echo "   - Impact: Kerberos requires <5 minute time skew"
            echo "   - Resolution: Enable NTP with \`sudo timedatectl set-ntp true\`"
            echo ""
        fi
    fi

    # Check 3: Docker sidecar
    if command -v docker >/dev/null 2>&1; then
        if ! docker ps 2>/dev/null | grep -q kerberos-platform-service; then
            ISSUES_FOUND=true
            echo "⚠️  **Kerberos sidecar not running**"
            echo "   - Impact: Containers cannot receive Kerberos tickets"
            echo "   - Resolution: Run \`make platform-start\` or \`docker compose up -d\`"
            echo ""
        fi
    fi

    # Check 4: SQL tools
    if ! command -v sqlcmd >/dev/null 2>&1 && [ ! -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
        ISSUES_FOUND=true
        echo "⚠️  **SQL Server tools not installed**"
        echo "   - Impact: Cannot test SQL Server authentication"
        echo "   - Resolution: Install mssql-tools18 package"
        echo ""
    fi

    if [ "$ISSUES_FOUND" = false ]; then
        echo "✅ **No obvious issues detected**"
        echo ""
        echo "Environment appears properly configured. If still experiencing issues:"
        echo "1. Run \`./krb5-auth-test.sh -v -s <sqlserver> -d <database>\` for detailed SQL testing"
        echo "2. Check SQL Server SPNs with your DBA"
        echo "3. Verify network connectivity to SQL Server port 1433"
    fi
    echo ""

    echo "## 📚 Context for LLM Analysis"
    echo ""
    echo "### What This System Does"
    echo ""
    echo "This is a Kerberos ticket-sharing sidecar system that allows Docker containers to use"
    echo "the host's Kerberos tickets for authentication to SQL Server and other Kerberized services."
    echo "The architecture involves:"
    echo ""
    echo "1. **Host System**: Obtains Kerberos tickets via \`kinit\`"
    echo "2. **Sidecar Container**: Monitors and shares tickets to other containers"
    echo "3. **Application Containers**: Mount shared ticket cache for authentication"
    echo ""

    echo "### Common Issues and Solutions"
    echo ""
    echo "1. **\"No credentials cache found\"**"
    echo "   - User hasn't run \`kinit\`"
    echo "   - KRB5CCNAME points to wrong location"
    echo ""
    echo "2. **\"Cannot authenticate using Kerberos\"**"
    echo "   - SQL Server SPN not registered"
    echo "   - Ticket not forwardable (\`kinit -f\`)"
    echo ""
    echo "3. **\"Login timeout expired\"**"
    echo "   - Network connectivity issue"
    echo "   - Wrong SQL Server hostname"
    echo "   - Not on VPN"
    echo ""

    echo "### Next Steps for Troubleshooting"
    echo ""
    echo "Based on the diagnostic data above, an LLM should:"
    echo "1. Identify which component is failing (Kerberos, Network, SQL, Docker)"
    echo "2. Suggest specific commands to gather more information"
    echo "3. Provide step-by-step resolution instructions"
    echo "4. Recommend verification commands to confirm the fix"
    echo ""

    echo "---"
    echo ""
    echo "## 🤝 How to Use This Report"
    echo ""
    echo "### For Humans"
    echo "Copy this entire report and paste it into ChatGPT or Claude with your question."
    echo "Example: \"Based on this diagnostic context, why am I getting 'Login failed for user'?\""
    echo ""
    echo "### For Developers"
    echo "This report structure is designed to be parsed by MCP-compatible agents in the future."
    echo "JSON output mode is available: \`$0 json diagnostic-context.json\`"
    echo ""
    echo "### For Support Teams"
    echo "This report contains all necessary information for remote troubleshooting without"
    echo "requiring additional back-and-forth for context gathering."
    echo ""
    echo "---"
    echo ""
    echo "*Generated by generate-diagnostic-context.sh v$VERSION*"

} > "$OUTPUT_FILE"

# Also generate JSON version if requested
if [ "$OUTPUT_FORMAT" = "json" ]; then
    JSON_FILE="${OUTPUT_FILE%.md}.json"

    # Create JSON structure
    cat > "$JSON_FILE" << EOF
{
  "version": "$VERSION",
  "timestamp": "$TIMESTAMP",
  "system": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "arch": "$(uname -m)",
    "user": "$(whoami)",
    "environment": "$(grep -q Microsoft /proc/version 2>/dev/null && echo 'WSL2' || ([ -f /.dockerenv ] && echo 'Container' || echo 'Native'))"
  },
  "kerberos": {
    "ticket_valid": $(klist -s 2>/dev/null && echo "true" || echo "false"),
    "krb5ccname": "${KRB5CCNAME:-default}",
    "config_exists": $([ -f /etc/krb5.conf ] && echo "true" || echo "false")
  },
  "docker": {
    "installed": $(command -v docker >/dev/null 2>&1 && echo "true" || echo "false"),
    "sidecar_running": $(docker ps 2>/dev/null | grep -q kerberos-platform-service && echo "true" || echo "false")
  },
  "sql_tools": {
    "sqlcmd_installed": $(command -v sqlcmd >/dev/null 2>&1 || [ -x "/opt/mssql-tools18/bin/sqlcmd" ] && echo "true" || echo "false")
  },
  "issues_detected": $ISSUES_FOUND
}
EOF

    echo -e "${GREEN}✓${NC} JSON diagnostic context saved to: $JSON_FILE"
fi

echo -e "${GREEN}✓${NC} Diagnostic context saved to: $OUTPUT_FILE"
echo ""
echo "To use this report:"
echo "1. Copy the contents of $OUTPUT_FILE"
echo "2. Paste into ChatGPT/Claude with your question"
echo "3. The LLM will have full context to help diagnose your issue"
echo ""
echo "Example prompt:"
echo "  'I'm getting \"Login failed for user\" when trying to connect to SQL Server."
echo "  Here's my diagnostic context: [paste report]'"
