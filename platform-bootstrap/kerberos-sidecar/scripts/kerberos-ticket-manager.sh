#!/bin/bash
# Kerberos Ticket Manager - Handles ticket acquisition and renewal
set -e

# Configuration from environment variables
PRINCIPAL="${KRB_PRINCIPAL}"
KEYTAB_PATH="${KRB_KEYTAB_PATH:-/krb5/keytabs/service.keytab}"
PASSWORD="${KRB_PASSWORD}"
REALM="${KRB_REALM}"
RENEWAL_INTERVAL="${KRB_RENEWAL_INTERVAL:-3600}"  # Default: 1 hour
USE_PASSWORD="${USE_PASSWORD:-false}"

# Structured logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >&2
}

# Function to obtain initial ticket
obtain_ticket() {
    log "Obtaining Kerberos ticket for principal: ${PRINCIPAL}"

    if [[ "${USE_PASSWORD}" == "true" ]]; then
        # Use password authentication (for development/testing)
        if [[ -z "${PASSWORD}" ]]; then
            log_error "Password authentication enabled but password not provided"
            log_error ""
            log_error "HOW TO FIX:"
            log_error "1. Add to your .env file:"
            log_error "   KRB_PASSWORD=your_password_here"
            log_error ""
            log_error "2. Or set in docker-compose.yml:"
            log_error "   environment:"
            log_error "     - KRB_PASSWORD=\${KRB_PASSWORD}"
            log_error ""
            log_error "3. Restart the service:"
            log_error "   make platform-restart"
            log_error ""
            log_error "NOTE: For production, use keytab authentication (USE_PASSWORD=false)"
            return 1
        fi
        log "Using password authentication for ${PRINCIPAL}"
        if echo "${PASSWORD}" | kinit "${PRINCIPAL}" 2>&1 | tee /tmp/kinit.log | while read line; do log "kinit: $line"; done; then
            log "Password authentication successful"
        else
            log_error "Password authentication failed for ${PRINCIPAL}"
            log_error ""
            log_error "HOW TO FIX:"
            log_error "1. Verify your password is correct"
            log_error "2. Check principal format is correct: user@DOMAIN.COM (uppercase domain)"
            log_error "3. Verify domain/realm matches your krb5.conf"
            log_error "4. Test manually: kinit ${PRINCIPAL}"
            log_error ""
            log_error "If still failing, contact IT/Domain Admin with:"
            log_error "  - Principal: ${PRINCIPAL}"
            log_error "  - Domain: ${REALM}"
            log_error "  - kinit error: $(cat /tmp/kinit.log 2>/dev/null | head -3)"
            return 1
        fi
    else
        # Use keytab authentication (production)
        if [[ ! -f "${KEYTAB_PATH}" ]]; then
            log_error "Keytab file not found at expected location: ${KEYTAB_PATH}"
            log_error ""
            log_error "HOW TO FIX:"
            log_error "1. Get keytab file from your DBA or Domain Admin"
            log_error "   Tell them: 'I need a keytab for service principal ${PRINCIPAL}'"
            log_error ""
            log_error "2. Mount the keytab in docker-compose.yml:"
            log_error "   volumes:"
            log_error "     - /path/on/host/service.keytab:${KEYTAB_PATH}:ro"
            log_error ""
            log_error "3. Set the path in .env if different from default:"
            log_error "   KRB_KEYTAB_PATH=${KEYTAB_PATH}"
            log_error ""
            log_error "4. Restart the service:"
            log_error "   make platform-restart"
            log_error ""
            log_error "For development/testing, you can use password auth instead:"
            log_error "   USE_PASSWORD=true"
            log_error "   KRB_PASSWORD=your_password"
            return 1
        fi
        log "Using keytab authentication from ${KEYTAB_PATH}"
        if kinit -kt "${KEYTAB_PATH}" "${PRINCIPAL}" 2>&1 | tee /tmp/kinit.log | while read line; do log "kinit: $line"; done; then
            log "Keytab authentication successful"
        else
            log_error "Keytab authentication failed"
            log_error ""
            log_error "HOW TO FIX:"
            log_error "1. Verify keytab contains the correct principal:"
            log_error "   klist -kt ${KEYTAB_PATH}"
            log_error "   Should show: ${PRINCIPAL}"
            log_error ""
            log_error "2. Check file permissions (must be readable):"
            log_error "   ls -la ${KEYTAB_PATH}"
            log_error ""
            log_error "3. Verify principal matches exactly (case-sensitive):"
            log_error "   Expected: ${PRINCIPAL}"
            log_error ""
            log_error "If keytab is wrong, contact DBA/Domain Admin with:"
            log_error "  - Principal needed: ${PRINCIPAL}"
            log_error "  - Current keytab error: $(cat /tmp/kinit.log 2>/dev/null | head -3)"
            log_error "  - Request: 'Please generate keytab with: ktutil or msktutil'"
            return 1
        fi
    fi

    # Copy ticket to shared location
    if [[ -f /tmp/krb5cc_0 ]]; then
        cp /tmp/krb5cc_0 /krb5/cache/krb5cc
        chmod 644 /krb5/cache/krb5cc
        log "Ticket cache copied to shared volume"
    fi

    # Verify ticket
    if klist -s; then
        log "Ticket obtained successfully"
        klist 2>&1 | while read line; do
            log "klist: $line"
        done
        return 0
    else
        log_error "Failed to obtain valid ticket (klist validation failed)"
        log_error "This usually means kinit succeeded but ticket wasn't written correctly"
        log_error ""
        log_error "Check:"
        log_error "  - KRB5CCNAME is set: ${KRB5CCNAME:-not set}"
        log_error "  - Cache directory exists and is writable: $(dirname ${KRB5CCNAME:-/krb5/cache/krb5cc})"
        return 1
    fi
}

# Function to check ticket validity
check_ticket() {
    if klist -s; then
        # Get ticket expiration time
        local expiry=$(klist | grep -E "^[[:space:]]*[0-9]" | head -1 | awk '{print $3, $4}')
        log "Ticket valid until: ${expiry}"
        return 0
    else
        log "Ticket expired or invalid"
        return 1
    fi
}

# Main loop
main() {
    log "Starting Kerberos Ticket Manager"
    log "Configuration:"
    log "  Principal: ${PRINCIPAL}"
    log "  Realm: ${REALM}"
    log "  Keytab: ${KEYTAB_PATH}"
    log "  Renewal Interval: ${RENEWAL_INTERVAL} seconds"

    # Validate required configuration
    if [[ -z "${PRINCIPAL}" ]]; then
        log_error "KRB_PRINCIPAL environment variable not set"
        log_error ""
        log_error "HOW TO FIX:"
        log_error "1. Add to your .env file:"
        log_error "   KRB_PRINCIPAL=your_username@DOMAIN.COM"
        log_error ""
        log_error "2. Replace 'your_username' with your Windows/AD username"
        log_error "3. Replace DOMAIN.COM with your Active Directory domain (uppercase)"
        log_error ""
        log_error "Example:"
        log_error "   KRB_PRINCIPAL=john.smith@COMPANY.COM"
        log_error ""
        log_error "Then restart: make platform-restart"
        exit 1
    fi

    # Initial ticket acquisition
    if ! obtain_ticket; then
        log_error "Initial ticket acquisition failed - container cannot start"
        log_error ""
        log_error "Review the error messages above for specific guidance"
        log_error "Or check the diagnostic tool: ./diagnose-kerberos.sh"
        exit 1
    fi

    # Renewal loop
    while true; do
        sleep "${RENEWAL_INTERVAL}"

        log "Checking ticket status..."
        if ! check_ticket; then
            log_warn "Ticket needs renewal"
            if ! obtain_ticket; then
                log_error "Ticket renewal failed - will retry in 60 seconds"
                # Continue trying instead of exiting
                sleep 60
                continue
            fi
        else
            log "Ticket still valid"
        fi

        # Also ensure the shared cache is up to date
        if [[ -f /tmp/krb5cc_0 ]]; then
            cp /tmp/krb5cc_0 /krb5/cache/krb5cc
        fi
    done
}

# Handle signals for graceful shutdown
trap 'log "Received shutdown signal"; kdestroy; exit 0' SIGTERM SIGINT

# Run main function
main
