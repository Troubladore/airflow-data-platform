#!/bin/bash
# Health check script for Kerberos sidecar
# Returns structured status for diagnostics

set -euo pipefail

# Output structured JSON status
output_status() {
    local status="$1"
    local message="$2"
    local expiry="${3:-}"
    local error_type="${4:-}"
    local fix_guidance="${5:-}"

    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"message\": \"$message\","
    if [ -n "$expiry" ]; then
        echo "  \"ticket_expiry\": \"$expiry\","
    fi
    if [ -n "$error_type" ]; then
        echo "  \"error_type\": \"$error_type\","
    fi
    if [ -n "$fix_guidance" ]; then
        echo "  \"fix_guidance\": \"$fix_guidance\","
    fi
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\""
    echo "}"
}

# Check if klist is available
if ! command -v klist >/dev/null 2>&1; then
    output_status "unhealthy" "klist command not found" "" "missing_tools" "Kerberos client tools not installed in container"
    exit 1
fi

# Check for valid ticket
if klist -s 2>/dev/null; then
    # Ticket exists and is valid - get expiration time
    EXPIRY=$(klist 2>/dev/null | grep -E "^[[:space:]]*[0-9]" | head -1 | awk '{print $3, $4}' || echo "unknown")

    # Get principal
    PRINCIPAL=$(klist 2>/dev/null | grep "Default principal:" | sed 's/Default principal: //' || echo "unknown")

    output_status "healthy" "Kerberos ticket is valid (principal: $PRINCIPAL)" "$EXPIRY"
    exit 0
else
    # No valid ticket - determine why by analyzing logs
    ERROR_TYPE="unknown"
    FIX_GUIDANCE="Check container logs with: docker logs kerberos-platform-service"

    # Check if ticket manager script is running
    if ! pgrep -f "kerberos-ticket-manager.sh" >/dev/null 2>&1; then
        ERROR_TYPE="ticket_manager_not_running"
        FIX_GUIDANCE="Ticket manager script is not running. Check if container started properly."
    else
        # Try to determine failure reason from recent behavior

        # Check for password/keytab configuration
        if [ "${USE_PASSWORD:-false}" == "true" ]; then
            if [ -z "${KRB_PASSWORD:-}" ]; then
                ERROR_TYPE="missing_password"
                FIX_GUIDANCE="Password authentication enabled but KRB_PASSWORD not set. Set KRB_PASSWORD in .env or docker-compose.yml"
            else
                ERROR_TYPE="password_auth_failed"
                FIX_GUIDANCE="Password authentication failed. Check password is correct and principal (${KRB_PRINCIPAL:-unset}) exists in domain"
            fi
        else
            # Keytab mode
            KEYTAB_PATH="${KRB_KEYTAB_PATH:-/krb5/keytabs/service.keytab}"
            if [ ! -f "$KEYTAB_PATH" ]; then
                ERROR_TYPE="missing_keytab"
                FIX_GUIDANCE="Keytab not found at $KEYTAB_PATH. Mount keytab with: -v /path/to/service.keytab:$KEYTAB_PATH:ro"
            else
                ERROR_TYPE="keytab_auth_failed"
                FIX_GUIDANCE="Keytab authentication failed. Verify keytab contains principal ${KRB_PRINCIPAL:-unset} with: klist -kt $KEYTAB_PATH"
            fi
        fi

        # Check if principal is set
        if [ -z "${KRB_PRINCIPAL:-}" ]; then
            ERROR_TYPE="missing_principal"
            FIX_GUIDANCE="KRB_PRINCIPAL environment variable not set. Set it in .env or docker-compose.yml (example: user@DOMAIN.COM)"
        fi
    fi

    output_status "unhealthy" "No valid Kerberos ticket" "" "$ERROR_TYPE" "$FIX_GUIDANCE"
    exit 1
fi
