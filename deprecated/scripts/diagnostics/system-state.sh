#!/bin/bash
# Comprehensive system state detection from WSL2
# Observes actual system state rather than tracking what we think we did

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# WINDOWS INTERACTION UTILITY
# ==============================================================================

# Detects working PowerShell command for Windows interaction from WSL2
detect_windows_powershell() {
    local powershell_candidates=(
        "powershell.exe"
        "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
        "pwsh.exe"
        "/mnt/c/Program Files/PowerShell/7/pwsh.exe"
    )

    for ps_cmd in "${powershell_candidates[@]}"; do
        if $ps_cmd -NoProfile -Command "Write-Output 'test'" &>/dev/null; then
            echo "$ps_cmd"
            return 0
        fi
    done

    return 1
}

# Global variables for Windows interaction
WINDOWS_PS=""
WINDOWS_ACCESSIBLE=false

# Initialize Windows interaction capability
init_windows_interaction() {
    if WINDOWS_PS=$(detect_windows_powershell); then
        WINDOWS_ACCESSIBLE=true
        echo "  🪟 Windows accessible via: $(basename "$WINDOWS_PS")"
    else
        WINDOWS_ACCESSIBLE=false
        echo "  ⚠️  Windows not accessible from this WSL2 session"
    fi
}

# ==============================================================================
# CERTIFICATE VERIFICATION UTILITY
# ==============================================================================

# Verifies what certificate a specific HTTPS endpoint is actually serving
# Returns: 0 if certificate matches hostname, 1 if mismatch, 2 if unreachable
verify_endpoint_certificate() {
    local hostname="$1"
    local port="${2:-443}"

    # Test connectivity first
    if ! curl -s --connect-timeout 5 --max-time 10 -k "https://$hostname:$port/" &>/dev/null; then
        echo "CERT_STATUS=unreachable"
        return 2
    fi

    # Get certificate details
    local cert_output
    if cert_output=$(openssl s_client -connect "$hostname:$port" -servername "$hostname" </dev/null 2>/dev/null | openssl x509 -text -noout 2>/dev/null); then
        # Extract SAN entries
        local san_entries
        san_entries=$(echo "$cert_output" | grep -A 1 "Subject Alternative Name" | grep -o "DNS:[^,]*" | sed 's/DNS://' | tr '\n' ',' | sed 's/,$//')

        echo "CERT_SAN=$san_entries"

        # Check if hostname matches any SAN entry
        local hostname_matches=false
        IFS=',' read -ra SAN_ARRAY <<< "$san_entries"
        for san_entry in "${SAN_ARRAY[@]}"; do
            san_entry=$(echo "$san_entry" | xargs) # trim whitespace
            # Handle wildcard matching
            if [[ "$san_entry" == \*.* ]]; then
                local wildcard_domain="${san_entry#\*.}"
                if [[ "$hostname" == *"$wildcard_domain" ]] && [[ "$hostname" != "$wildcard_domain" ]]; then
                    hostname_matches=true
                    break
                fi
            elif [[ "$san_entry" == "$hostname" ]]; then
                hostname_matches=true
                break
            fi
        done

        if $hostname_matches; then
            echo "CERT_STATUS=valid"
            return 0
        else
            echo "CERT_STATUS=hostname_mismatch"
            return 1
        fi
    else
        echo "CERT_STATUS=cert_read_error"
        return 2
    fi
}

# ==============================================================================
# WINDOWS STATE DETECTION FROM WSL2
# ==============================================================================

detect_windows_certificates() {
    echo "🔐 Certificate State Detection"

    # Check if mkcert is installed (WSL2 or Windows)
    local mkcert_installed=false
    if command -v mkcert &>/dev/null; then
        mkcert_installed=true
        echo "  ✅ mkcert: Installed (WSL2)"
    elif [ "$WINDOWS_ACCESSIBLE" = true ] && $WINDOWS_PS -NoProfile -Command "Get-Command mkcert -ErrorAction SilentlyContinue" &>/dev/null; then
        mkcert_installed=true
        echo "  ✅ mkcert: Installed (Windows)"
    else
        echo "  ❌ mkcert: Not installed"
    fi

    # Check for certificate files (multiple possible locations)
    local cert_locations=(
        "$HOME/.local/share/certs"
        "/mnt/c/Users/$USER/AppData/Local/mkcert"
        "/mnt/c/Users/$USER/.local/share/mkcert"
    )

    local certs_found=false
    local cert_location=""

    for location in "${cert_locations[@]}"; do
        if [ -f "$location/dev-localhost-wild.crt" ]; then
            certs_found=true
            cert_location="$location"
            break
        fi
    done

    if $certs_found; then
        echo "  ✅ Certificates: Found in $cert_location"

        # Check certificate validity and expiration
        local cert_file="$cert_location/dev-localhost-wild.crt"
        if openssl x509 -in "$cert_file" -noout -checkend 2592000 &>/dev/null; then
            echo "  ✅ Certificate validity: Valid (>30 days)"
        else
            echo "  ⚠️  Certificate validity: Expires soon or invalid"
        fi

        # Check SAN entries
        local san_check=$(openssl x509 -in "$cert_file" -text -noout | grep -A1 "Subject Alternative Name" | grep -o "DNS:[^,]*" | wc -l)
        echo "  ✅ SAN entries: $san_check domains found"
    else
        echo "  ❌ Certificates: Not found in any expected location"
    fi

    # Check Windows certificate store (mkcert CA) with pollution detection
    local ca_status=""
    if [ "$WINDOWS_ACCESSIBLE" = true ]; then
        ca_status=$($WINDOWS_PS -NoProfile -Command "
            try {
                \$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
                \$store.Open('ReadOnly')
                \$certs = \$store.Certificates | Where-Object { \$_.Subject -like '*mkcert*' }
                \$store.Close()

                if (\$certs.Count -eq 0) {
                    Write-Output 'CA_STATUS=missing'
                } elseif (\$certs.Count -eq 1) {
                    \$cert = \$certs[0]
                    \$daysUntilExpiry = (\$cert.NotAfter - (Get-Date)).Days
                    if (\$daysUntilExpiry -lt 30) {
                        Write-Output \"CA_STATUS=expires_soon CA_COUNT=1 CA_DAYS_LEFT=\$daysUntilExpiry\"
                    } else {
                        Write-Output \"CA_STATUS=good CA_COUNT=1 CA_DAYS_LEFT=\$daysUntilExpiry\"
                    }
                } else {
                    \$latestCert = \$certs | Sort-Object NotAfter -Descending | Select-Object -First 1
                    \$oldestDate = (\$certs | Sort-Object NotBefore | Select-Object -First 1).NotBefore
                    \$latestDate = \$latestCert.NotBefore
                    \$daySpread = (\$latestDate - \$oldestDate).Days
                    Write-Output \"CA_STATUS=polluted CA_COUNT=\$(\$certs.Count) CA_DATE_SPREAD=\$daySpread\"
                }
            } catch {
                Write-Output 'CA_STATUS=error'
            }
        " 2>/dev/null)

        if [[ "$ca_status" == *"CA_STATUS=missing"* ]]; then
            echo "  ❌ Windows CA trust: mkcert CA not found"
        elif [[ "$ca_status" == *"CA_STATUS=good"* ]]; then
            local ca_days=$(echo "$ca_status" | grep -o "CA_DAYS_LEFT=[0-9]*" | cut -d= -f2)
            echo "  ✅ Windows CA trust: mkcert CA installed (expires in $ca_days days)"
        elif [[ "$ca_status" == *"CA_STATUS=expires_soon"* ]]; then
            local ca_days=$(echo "$ca_status" | grep -o "CA_DAYS_LEFT=[0-9]*" | cut -d= -f2)
            echo "  ⚠️  Windows CA trust: mkcert CA expires in $ca_days days"
        elif [[ "$ca_status" == *"CA_STATUS=polluted"* ]]; then
            local ca_count=$(echo "$ca_status" | grep -o "CA_COUNT=[0-9]*" | cut -d= -f2)
            local date_spread=$(echo "$ca_status" | grep -o "CA_DATE_SPREAD=[0-9]*" | cut -d= -f2)
            echo "  ❌ Windows CA trust: POLLUTED - $ca_count mkcert CAs found (spanning $date_spread days)"
            echo "     💡 Multiple CA certificates cause browser trust warnings"
        else
            echo "  ❌ Windows CA trust: Error checking certificate store"
        fi
    else
        echo "  ⚠️  Windows CA trust: Cannot check (Windows not accessible)"
    fi

    return 0
}

detect_windows_hosts() {
    echo "🌐 Hosts File State Detection"

    local required_hosts=("registry.localhost" "traefik.localhost" "airflow.localhost")
    local hosts_ok=true

    for host in "${required_hosts[@]}"; do
        if getent hosts "$host" &>/dev/null; then
            echo "  ✅ $host: Resolves to $(getent hosts "$host" | awk '{print $1}')"
        else
            echo "  ❌ $host: Does not resolve"
            hosts_ok=false
        fi
    done

    # Also check Windows hosts file directly
    local windows_hosts="/mnt/c/Windows/System32/drivers/etc/hosts"
    if [ -f "$windows_hosts" ]; then
        local missing_entries=()
        for host in "${required_hosts[@]}"; do
            if ! grep -q "127.0.0.1[[:space:]]*$host" "$windows_hosts"; then
                missing_entries+=("$host")
            fi
        done

        if [ ${#missing_entries[@]} -eq 0 ]; then
            echo "  ✅ Windows hosts file: All entries present"
        else
            echo "  ⚠️  Windows hosts file: Missing ${missing_entries[*]}"
        fi
    else
        echo "  ❌ Windows hosts file: Cannot access"
    fi

    return 0
}

# ==============================================================================
# DOCKER STATE DETECTION
# ==============================================================================

detect_docker_state() {
    echo "🐳 Docker State Detection"

    # Check Docker CLI availability
    if command -v docker &>/dev/null; then
        echo "  ✅ Docker CLI: Available"
    else
        echo "  ❌ Docker CLI: Not found"
        return 1
    fi

    # Check Docker daemon connectivity
    if docker info &>/dev/null; then
        echo "  ✅ Docker daemon: Running and accessible"

        # Check Docker Desktop proxy configuration
        local proxy_config=$(docker info --format '{{.HTTPProxy}}' 2>/dev/null || echo "")
        local no_proxy_config=$(docker info --format '{{.NoProxy}}' 2>/dev/null || echo "")

        if [ -n "$proxy_config" ]; then
            echo "  ℹ️  Docker proxy: $proxy_config"
            if [[ "$no_proxy_config" == *"*.localhost"* ]]; then
                echo "  ✅ Proxy bypass: *.localhost configured"
            else
                echo "  ⚠️  Proxy bypass: *.localhost missing"
            fi
        else
            echo "  ✅ Docker proxy: None configured"
        fi

    else
        echo "  ❌ Docker daemon: Not accessible"

        # Try to diagnose the issue
        if docker version &>/dev/null; then
            echo "    💡 Docker CLI works but daemon unreachable (Start Docker Desktop)"
        else
            echo "    💡 Docker integration not configured (Enable WSL2 integration)"
        fi
        return 1
    fi

    return 0
}

# ==============================================================================
# PLATFORM SERVICES STATE DETECTION
# ==============================================================================

detect_platform_services() {
    echo "🚀 Platform Services State Detection"

    # Check if platform services exist
    local platform_services_dir="$HOME/platform-services/traefik"
    if [ -d "$platform_services_dir" ]; then
        echo "  ✅ Platform services: Directory exists"

        # Check if services are running
        if docker ps --format "{{.Names}}" | grep -q "traefik\|registry"; then
            echo "  ✅ Platform containers: Running"
            docker ps --format "    {{.Names}}: {{.Status}}" | grep -E "(traefik|registry)"
        else
            echo "  ❌ Platform containers: Not running"
        fi

    else
        echo "  ❌ Platform services: Not generated"
    fi

    # Check network connectivity to platform services
    local endpoints=(
        "traefik.localhost/api/http/services"
        "registry.localhost/v2/_catalog"
    )

    for endpoint in "${endpoints[@]}"; do
        if curl -s --connect-timeout 5 "https://$endpoint" &>/dev/null || \
           curl -s -k --connect-timeout 5 "https://$endpoint" &>/dev/null; then
            echo "  ✅ $endpoint: Accessible"
        else
            echo "  ❌ $endpoint: Not accessible"
        fi
    done

    return 0
}

# ==============================================================================
# NETWORK STATE DETECTION
# ==============================================================================

detect_network_state() {
    echo "🌐 Network State Detection"

    # Test external connectivity (for Docker Hub, etc.)
    if curl -s --connect-timeout 10 "https://registry-1.docker.io/v2/" &>/dev/null; then
        echo "  ✅ External connectivity: Docker Hub accessible"
    else
        echo "  ⚠️  External connectivity: Docker Hub unreachable"
    fi

    # Test Docker network
    if docker network ls | grep -q "edge"; then
        echo "  ✅ Docker networks: Edge network exists"
    else
        echo "  ❌ Docker networks: Edge network missing"
    fi

    return 0
}

# ==============================================================================
# MAIN DIAGNOSTIC RUNNER
# ==============================================================================

main() {
    echo "🔍 System State Diagnostic Report"
    echo "=================================="
    echo

    # Initialize Windows interaction capability
    init_windows_interaction
    echo

    local overall_status=0

    detect_windows_certificates || overall_status=1
    echo

    detect_windows_hosts || overall_status=1
    echo

    detect_docker_state || overall_status=1
    echo

    detect_platform_services || overall_status=1
    echo

    detect_network_state || overall_status=1
    echo

    echo "=================================="
    if [ $overall_status -eq 0 ]; then
        echo "🎉 Overall Status: All systems operational"
    else
        echo "⚠️  Overall Status: Issues detected (see above)"
    fi

    return $overall_status
}

# Run diagnostics if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
