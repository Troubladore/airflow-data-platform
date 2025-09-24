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

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to obtain initial ticket
obtain_ticket() {
    log "Obtaining Kerberos ticket for principal: ${PRINCIPAL}"

    if [[ "${USE_PASSWORD}" == "true" ]]; then
        # Use password authentication (for development/testing)
        if [[ -z "${PASSWORD}" ]]; then
            log "ERROR: Password not provided for password authentication"
            return 1
        fi
        echo "${PASSWORD}" | kinit "${PRINCIPAL}" 2>&1 | while read line; do
            log "kinit: $line"
        done
    else
        # Use keytab authentication (production)
        if [[ ! -f "${KEYTAB_PATH}" ]]; then
            log "ERROR: Keytab file not found at ${KEYTAB_PATH}"
            return 1
        fi
        kinit -kt "${KEYTAB_PATH}" "${PRINCIPAL}" 2>&1 | while read line; do
            log "kinit: $line"
        done
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
        log "ERROR: Failed to obtain valid ticket"
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
        log "ERROR: KRB_PRINCIPAL environment variable not set"
        exit 1
    fi

    # Initial ticket acquisition
    if ! obtain_ticket; then
        log "ERROR: Initial ticket acquisition failed"
        exit 1
    fi

    # Renewal loop
    while true; do
        sleep "${RENEWAL_INTERVAL}"

        log "Checking ticket status..."
        if ! check_ticket; then
            log "Ticket needs renewal"
            if ! obtain_ticket; then
                log "ERROR: Ticket renewal failed"
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
