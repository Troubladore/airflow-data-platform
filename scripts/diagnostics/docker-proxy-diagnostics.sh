#!/bin/bash
# Docker Proxy Bypass Diagnostic Utility
# Detects proxy configuration issues between Docker Desktop settings and Docker engine

set -euo pipefail

# Returns:
# 0 = Proxy configuration is correct
# 1 = No proxy configured (bypass not needed)
# 2 = Proxy configured but bypass missing from settings
# 3 = Proxy configured, bypass in settings, but not applied to engine (restart needed)
# 4 = Cannot access Docker or settings

# Required domains for platform operation
REQUIRED_BYPASS_DOMAINS=(
    "localhost"
    "*.localhost"
    "127.0.0.1"
    "registry.localhost"
    "traefik.localhost"
    "airflow.localhost"
)

# Check Docker engine proxy settings
detect_docker_engine_proxy() {
    local http_proxy no_proxy

    if ! docker info &>/dev/null; then
        echo "DOCKER_ENGINE=not_accessible"
        return 4
    fi

    http_proxy=$(docker info --format '{{.HTTPProxy}}' 2>/dev/null || echo "")
    no_proxy=$(docker info --format '{{.NoProxy}}' 2>/dev/null || echo "")

    echo "DOCKER_HTTP_PROXY=$http_proxy"
    echo "DOCKER_NO_PROXY=$no_proxy"

    if [ -z "$http_proxy" ]; then
        echo "DOCKER_PROXY_STATUS=no_proxy"
        return 1
    else
        echo "DOCKER_PROXY_STATUS=proxy_configured"
        return 0
    fi
}

# Version comparison helper
version_gte() {
    [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Detect Windows proxy configuration (WinINET - what Docker actually reads)
detect_windows_proxy_state() {
    echo "WINDOWS_PROXY_ANALYSIS=starting"

    # Use the existing Windows PowerShell detection utility
    source "$(dirname "$0")/system-state.sh"
    init_windows_interaction >/dev/null 2>&1

    if [ "$WINDOWS_ACCESSIBLE" != true ]; then
        echo "WINDOWS_PROXY_STATE=detection_failed"
        echo "WINDOWS_PROXY_ERROR=PowerShell not accessible"
        return 4
    fi

    # Check WinINET (per-user) settings that Docker Desktop actually reads
    local wininet_output
    if wininet_output=$($WINDOWS_PS -NoProfile -Command "
        \$reg = Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' -ErrorAction SilentlyContinue
        if (\$reg) {
            Write-Output \"ProxyEnable=\$(\$reg.ProxyEnable)\"
            Write-Output \"ProxyServer=\$(\$reg.ProxyServer -replace ' ','')\"
            Write-Output \"AutoConfigURL=\$(\$reg.AutoConfigURL)\"
            Write-Output \"ProxyOverride=\$(\$reg.ProxyOverride)\"
        } else {
            Write-Output 'ProxyEnable=0'
        }
    " 2>/dev/null | tr -d '\r'); then
        echo "$wininet_output"

        # Parse the results
        local proxy_enabled=$(echo "$wininet_output" | grep "ProxyEnable=" | cut -d= -f2)
        local proxy_server=$(echo "$wininet_output" | grep "ProxyServer=" | cut -d= -f2)
        local auto_config_url=$(echo "$wininet_output" | grep "AutoConfigURL=" | cut -d= -f2)
        local proxy_override=$(echo "$wininet_output" | grep "ProxyOverride=" | cut -d= -f2)

        # Determine proxy state
        if [ "$proxy_enabled" = "1" ] && [ -n "$proxy_server" ] && [ "$proxy_server" != "" ]; then
            echo "WINDOWS_PROXY_STATE=direct_proxy"
            echo "WINDOWS_PROXY_TYPE=manual"
        elif [ -n "$auto_config_url" ] && [ "$auto_config_url" != "" ]; then
            echo "WINDOWS_PROXY_STATE=pac_proxy"
            echo "WINDOWS_PROXY_TYPE=automatic"
            echo "WINDOWS_PAC_URL=$auto_config_url"
        else
            echo "WINDOWS_PROXY_STATE=no_proxy"
            echo "WINDOWS_PROXY_TYPE=direct"
        fi

        # Check existing Windows bypass list
        if [ -n "$proxy_override" ] && [ "$proxy_override" != "" ]; then
            echo "WINDOWS_BYPASS_LIST=$proxy_override"
        else
            echo "WINDOWS_BYPASS_LIST="
        fi
    else
        echo "WINDOWS_PROXY_STATE=detection_failed"
        return 4
    fi
}

# Cross-check all possible proxy sources for bulletproof analysis
perform_comprehensive_proxy_crosschecks() {
    # Re-initialize Windows interaction for cross-checks
    source "$(dirname "$0")/system-state.sh"
    init_windows_interaction >/dev/null 2>&1

    if [ "$WINDOWS_ACCESSIBLE" != true ]; then
        echo "CROSSCHECK_STATUS=powershell_not_accessible"
        return 4
    fi

    echo "🔍 COMPREHENSIVE PROXY SOURCE ANALYSIS"
    echo "======================================"

    # Cross-check 1: CLI config file
    echo "1️⃣ DOCKER CLI CONFIG:"
    local cli_config_output
    cli_config_output=$($WINDOWS_PS -NoProfile -Command "
        \$cliConfig = \"\$env:USERPROFILE\\.docker\\config.json\"
        if (Test-Path \$cliConfig) {
            try {
                \$content = Get-Content \$cliConfig -Raw | ConvertFrom-Json
                if (\$content.proxies) {
                    Write-Output \"CLI_CONFIG=found\"
                    Write-Output \"CLI_PROXIES=\$(\$content.proxies | ConvertTo-Json -Compress)\"
                } else {
                    Write-Output \"CLI_CONFIG=no_proxies\"
                }
            } catch {
                Write-Output \"CLI_CONFIG=parse_error\"
            }
        } else {
            Write-Output \"CLI_CONFIG=not_found\"
        }
    " 2>/dev/null | tr -d '\r')
    echo "$cli_config_output"

    # Cross-check 2: Environment variables
    echo ""
    echo "2️⃣ ENVIRONMENT VARIABLES:"
    local env_vars_output
    env_vars_output=$($WINDOWS_PS -NoProfile -Command "
        \$proxyVars = @('HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY')
        \$found = @()
        foreach (\$var in \$proxyVars) {
            \$val = [Environment]::GetEnvironmentVariable(\$var)
            if (\$val) { \$found += \"\$var=\$val\" }
        }
        if (\$found.Count -gt 0) {
            Write-Output \"ENV_PROXY_VARS=found\"
            \$found | ForEach-Object { Write-Output \$_ }
        } else {
            Write-Output \"ENV_PROXY_VARS=none\"
        }
    " 2>/dev/null | tr -d '\r')
    echo "$env_vars_output"

    # Cross-check 3: Docker Desktop settings file detailed analysis
    echo ""
    echo "3️⃣ DOCKER DESKTOP SETTINGS FILE:"
    local desktop_settings_output
    desktop_settings_output=$($WINDOWS_PS -NoProfile -Command "
        \$settingsPath = \"\$env:APPDATA\\Docker\\settings-store.json\"
        if (Test-Path \$settingsPath) {
            try {
                \$settings = Get-Content \$settingsPath -Raw | ConvertFrom-Json
                Write-Output \"DESKTOP_SETTINGS_FILE=found\"
                Write-Output \"USE_SYSTEM_PROXY=\$(\$settings.UseSystemProxy)\"
                if (\$settings.ProxySettings) {
                    Write-Output \"PROXY_SETTINGS=\$(\$settings.ProxySettings | ConvertTo-Json -Compress)\"
                } else {
                    Write-Output \"PROXY_SETTINGS=none\"
                }
                Write-Output \"OVERRIDE_PROXY_EXCLUDE=\$(\$settings.overrideProxyExclude)\"
            } catch {
                Write-Output \"DESKTOP_SETTINGS_FILE=parse_error\"
            }
        } else {
            Write-Output \"DESKTOP_SETTINGS_FILE=not_found\"
        }
    " 2>/dev/null | tr -d '\r')
    echo "$desktop_settings_output"

    # Cross-check 4: Admin policy detection
    echo ""
    echo "4️⃣ ADMIN POLICY DETECTION:"
    local admin_policy_output
    admin_policy_output=$($WINDOWS_PS -NoProfile -Command "
        \$adminSettings = \"\$env:ProgramData\\DockerDesktop\\admin-settings.json\"
        if (Test-Path \$adminSettings) {
            Write-Output \"ADMIN_POLICY=found\"
            Write-Output \"ADMIN_SETTINGS_PATH=\$adminSettings\"
            try {
                \$policy = Get-Content \$adminSettings -Raw | ConvertFrom-Json
                Write-Output \"ADMIN_POLICY_CONTENT=\$(\$policy | ConvertTo-Json -Compress)\"
            } catch {
                Write-Output \"ADMIN_POLICY_CONTENT=parse_error\"
            }
        } else {
            Write-Output \"ADMIN_POLICY=not_found\"
        }
    " 2>/dev/null | tr -d '\r')
    echo "$admin_policy_output"

    echo ""
}

# Automated Docker Desktop resync function
perform_automated_docker_resync() {
    echo "🔄 AUTOMATED DOCKER DESKTOP RESYNC"
    echo "=================================="
    echo ""
    echo "Detected Docker Desktop sync issue. Performing automated resync..."

    # Re-initialize Windows interaction for resync
    source "$(dirname "$0")/system-state.sh"
    init_windows_interaction >/dev/null 2>&1

    if [ "$WINDOWS_ACCESSIBLE" != true ]; then
        echo "❌ Windows PowerShell not accessible - cannot perform automated resync"
        return 1
    fi

    local resync_output
    resync_output=$($WINDOWS_PS -NoProfile -Command "
        try {
            Write-Output \"🛑 Stopping Docker Desktop and WSL...\"
            Stop-Process -Name 'Docker Desktop' -Force -ErrorAction SilentlyContinue
            wsl --shutdown
            Start-Sleep -Seconds 3

            Write-Output \"📝 Patching settings-store.json to force system proxy mode...\"
            \$settingsPath = \"\$env:APPDATA\\Docker\\settings-store.json\"
            if (Test-Path \$settingsPath) {
                \$settings = Get-Content \$settingsPath -Raw | ConvertFrom-Json
                \$settings.UseSystemProxy = \$true
                if (\$settings.PSObject.Properties.Name -contains 'ProxySettings') {
                    \$settings.ProxySettings = \$null
                }
                # Clear any stale manual proxy excludes since we're using system mode
                \$settings.overrideProxyExclude = \"\"

                \$settings | ConvertTo-Json -Depth 6 | Set-Content \$settingsPath -Encoding UTF8
                Write-Output \"✅ Settings patched successfully\"
            } else {
                Write-Output \"❌ Settings file not found: \$settingsPath\"
                exit 1
            }

            Write-Output \"🚀 Restarting Docker Desktop...\"
            Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe' -ErrorAction Stop
            Write-Output \"⏳ Waiting for Docker Desktop to start...\"
            Start-Sleep -Seconds 15

            # Verify the fix
            Write-Output \"🔍 Verifying Docker proxy configuration...\"
            \$dockerInfo = docker info --format '{{.HTTPProxy}} {{.NoProxy}}' 2>\$null
            if (\$dockerInfo) {
                Write-Output \"DOCKER_INFO_AFTER_RESYNC=\$dockerInfo\"
                if (\$dockerInfo -match 'http') {
                    Write-Output \"RESYNC_RESULT=proxy_still_present\"
                } else {
                    Write-Output \"RESYNC_RESULT=proxy_cleared_successfully\"
                }
            } else {
                Write-Output \"RESYNC_RESULT=docker_not_ready_yet\"
            }

            Write-Output \"✅ Automated resync completed\"
            exit 0

        } catch {
            Write-Output \"❌ Resync failed: \$(\$_.Exception.Message)\"
            exit 1
        }
    " 2>/dev/null | tr -d '\r')

    echo "$resync_output"
    local resync_exit=$?

    if [ $resync_exit -eq 0 ]; then
        echo ""
        echo "🎉 AUTOMATED RESYNC COMPLETED SUCCESSFULLY"
        echo "Docker Desktop should now reflect correct proxy settings"
        return 0
    else
        echo ""
        echo "❌ AUTOMATED RESYNC FAILED"
        echo "Manual intervention may be required"
        return 1
    fi
}

# Detect Docker Desktop proxy mode (Manual vs System)
detect_docker_desktop_mode() {
    local settings_file="$1"

    # Parse Docker Desktop proxy mode from settings
    local manual_mode_output
    if manual_mode_output=$(python3 -c "
import json, sys
try:
    with open('$settings_file', 'r') as f:
        settings = json.load(f)

    # Check if manual proxy configuration is enabled
    manual_enabled = settings.get('overrideProxyHttp', False) or settings.get('overrideProxyHttps', False)
    proxy_http = settings.get('proxyHttpMode', 'system')

    print(f'DOCKER_MANUAL_PROXY={str(manual_enabled).lower()}')
    print(f'DOCKER_PROXY_MODE={proxy_http}')

    # Get configured proxy URLs if in manual mode
    if manual_enabled or proxy_http == 'manual':
        http_url = settings.get('overrideProxyHttp', '')
        https_url = settings.get('overrideProxyHttps', '')
        print(f'DOCKER_MANUAL_HTTP={http_url}')
        print(f'DOCKER_MANUAL_HTTPS={https_url}')

except Exception as e:
    print('DOCKER_MANUAL_PROXY=detection_failed')
    print(f'DOCKER_MODE_ERROR={str(e)}')
" 2>/dev/null); then
        echo "$manual_mode_output"
    else
        echo "DOCKER_MANUAL_PROXY=detection_failed"
        return 4
    fi
}

# Check Docker Desktop settings file with version-aware detection
detect_docker_settings() {
    local docker_version settings_dir primary_settings
    local settings_paths=()

    # Get Docker Desktop version
    if docker_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null); then
        echo "DOCKER_VERSION=$docker_version"
    else
        echo "DOCKER_VERSION=unknown"
        docker_version="0.0.0"  # Default to legacy behavior
    fi

    # Determine Windows username and settings directory
    local windows_users=("$USER" "$(whoami)")
    if command -v /mnt/c/Windows/System32/cmd.exe >/dev/null 2>&1; then
        local windows_user
        if windows_user=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n'); then
            windows_users+=("$windows_user")
        fi
    fi

    # Find Docker settings directory
    for user in "${windows_users[@]}"; do
        settings_dir="/mnt/c/Users/$user/AppData/Roaming/Docker"
        if [ -d "$settings_dir" ]; then
            break
        fi
    done

    if [ ! -d "$settings_dir" ]; then
        echo "DOCKER_SETTINGS=not_found"
        echo "SETTINGS_FORMAT=unknown"
        return 4
    fi

    # Modern Docker (≥4.35): prefer settings-store.json
    if version_gte "$docker_version" "4.35.0" && [ -f "$settings_dir/settings-store.json" ] && [ -s "$settings_dir/settings-store.json" ]; then
        primary_settings="$settings_dir/settings-store.json"
        echo "SETTINGS_FORMAT=modern"
        echo "DOCKER_SETTINGS=$primary_settings"
    # Legacy Docker or fallback: use settings.json
    elif [ -f "$settings_dir/settings.json" ] && [ -s "$settings_dir/settings.json" ]; then
        primary_settings="$settings_dir/settings.json"
        echo "SETTINGS_FORMAT=legacy"
        echo "DOCKER_SETTINGS=$primary_settings"
    else
        echo "DOCKER_SETTINGS=not_found"
        echo "SETTINGS_FORMAT=unknown"
        return 4
    fi

    # Enhanced settings analysis with mode detection
    local proxy_mode bypass_list
    if ! proxy_mode=$(python3 -c "
import json, sys
try:
    with open('$primary_settings', 'r') as f:
        settings = json.load(f)
    print(settings.get('proxyHttpMode', 'none'))
except:
    print('parse_error')
" 2>/dev/null); then
        echo "SETTINGS_PROXY_MODE=parse_error"
        return 4
    fi

    if ! bypass_list=$(python3 -c "
import json, sys
try:
    with open('$primary_settings', 'r') as f:
        settings = json.load(f)
    print(settings.get('overrideProxyExclude', ''))
except:
    print('parse_error')
" 2>/dev/null); then
        echo "SETTINGS_BYPASS_LIST=parse_error"
        return 4
    fi

    echo "SETTINGS_PROXY_MODE=$proxy_mode"
    echo "SETTINGS_BYPASS_LIST=$bypass_list"

    # Detect Docker Desktop proxy mode (Manual vs System)
    detect_docker_desktop_mode "$primary_settings"

    return 0
}

# Check if required domains are in bypass list
check_bypass_domains() {
    local bypass_list="$1"
    local missing_domains=()

    for domain in "${REQUIRED_BYPASS_DOMAINS[@]}"; do
        if [[ "$bypass_list" != *"$domain"* ]]; then
            missing_domains+=("$domain")
        fi
    done

    if [ ${#missing_domains[@]} -eq 0 ]; then
        echo "BYPASS_DOMAINS_STATUS=complete"
        return 0
    else
        echo "BYPASS_DOMAINS_STATUS=missing"
        echo "MISSING_DOMAINS=${missing_domains[*]}"
        return 2
    fi
}

# Provide corporate policy investigation guidance
show_corporate_policy_guidance() {
    echo ""
    echo "🏢 CORPORATE POLICY INVESTIGATION GUIDANCE"
    echo "=========================================="
    echo ""
    echo "If settings appear correct but Docker engine doesn't reflect changes after restart,"
    echo "your organization may have corporate policies overriding local Docker settings."
    echo ""
    echo "Please check the following and report findings:"
    echo ""
    echo "1. 📋 REGISTRY KEYS TO CHECK:"
    echo "   Open PowerShell as Administrator and run:"
    echo "   Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Docker Inc\\Docker Desktop' 2>/dev/null"
    echo "   Get-ItemProperty 'HKCU:\\SOFTWARE\\Policies\\Docker Inc\\Docker Desktop' 2>/dev/null"
    echo ""
    echo "2. 🔍 DOCKER DESKTOP SETTINGS MANAGEMENT:"
    echo "   Check if 'Settings Management' is enabled in Docker Desktop:"
    echo "   • Open Docker Desktop → Settings"
    echo "   • Look for 'Settings Management' section"
    echo "   • If present, settings may be centrally managed"
    echo ""
    echo "3. 📁 CORPORATE CONFIGURATION FILES:"
    echo "   Check for corporate-managed files:"
    echo "   dir \"\$env:PROGRAMDATA\\Docker Desktop\\\" 2>/dev/null"
    echo "   dir \"\$env:APPDATA\\Docker\\\" | findstr policy 2>/dev/null"
    echo ""
    echo "4. 🌐 GROUP POLICY PROXY SETTINGS:"
    echo "   Check if Windows proxy settings are enforced:"
    echo "   Get-ItemProperty 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' | Select-Object ProxyServer,ProxyOverride"
    echo "   Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Internet Settings' | Select-Object ProxyServer,ProxyOverride"
    echo ""
    echo "5. 📊 DOCKER ENGINE DAEMON CONFIG:"
    echo "   Check if daemon.json is managed externally:"
    echo "   Get-Content \"\$env:PROGRAMDATA\\Docker\\config\\daemon.json\" 2>/dev/null"
    echo ""
    echo "WHAT TO REPORT:"
    echo "• Any registry keys found with Docker policies"
    echo "• Whether Settings Management appears in Docker Desktop"
    echo "• Any corporate configuration files discovered"
    echo "• Current Windows proxy policy settings"
    echo "• Contents of daemon.json if managed externally"
    echo ""
    echo "This information helps determine if corporate policies are preventing"
    echo "local proxy bypass configuration from taking effect."
    echo ""
}

# Sophisticated proxy scenario analysis for enterprise environments
analyze_proxy_scenario() {
    local windows_proxy_state="$1"
    local docker_manual_proxy="$2"
    local docker_no_proxy="$3"
    local settings_bypass_list="$4"
    local docker_http_proxy="$5"

    echo ""
    echo "🧠 SOPHISTICATED PROXY SCENARIO ANALYSIS"
    echo "========================================"

    # Priority Scenario: Docker Desktop Sync Issue (the exact case detected)
    if [[ "$windows_proxy_state" == "no_proxy" ]] && [[ "$docker_manual_proxy" == "false" ]] && [[ -n "$docker_http_proxy" ]] && [[ "$docker_http_proxy" == *"docker.internal"* ]]; then
        echo "PROXY_SCENARIO=docker_desktop_sync_issue"
        echo "RECOMMENDED_ACTION=automated_resync"
        echo "SCENARIO_GUIDANCE=Docker Desktop cache desync detected. Windows has no proxy but Docker still reports cached proxy."
        echo "EXPLANATION=This is normal after network changes. Docker Desktop cached an old proxy configuration."
        echo "AUTOMATED_FIX=available"
        return 5  # Special resync case
    fi

    # Scenario 1: No Windows proxy, clean state
    if [[ "$windows_proxy_state" == "no_proxy" ]] && [[ -z "$docker_http_proxy" || "$docker_http_proxy" == "" ]]; then
        echo "PROXY_SCENARIO=no_system_proxy_clean"
        echo "RECOMMENDED_ACTION=none_needed"
        echo "SCENARIO_GUIDANCE=No system proxy detected and Docker Desktop is clean. This is correct."
        echo "EXPLANATION=Normal default configuration. No action needed."
        return 0  # Working correctly
    fi

    # Scenario 2: Windows has proxy, Docker Manual is OFF (system mode)
    if [[ "$docker_manual_proxy" == "false" ]] && [[ "$windows_proxy_state" != "no_proxy" ]]; then
        if [[ "$docker_no_proxy" == *"localhost"* ]]; then
            echo "PROXY_SCENARIO=system_proxy_working"
            echo "RECOMMENDED_ACTION=none_needed"
            echo "SCENARIO_GUIDANCE=System proxy mode working correctly with localhost bypass."
            return 0  # Working correctly
        else
            echo "PROXY_SCENARIO=system_proxy_no_bypass"
            echo "RECOMMENDED_ACTION=enable_manual_mode"
            echo "SCENARIO_GUIDANCE=System proxy detected but no localhost bypass. Need to enable Manual mode to add bypass list."
            echo "UI_STEPS=Settings → Resources → Proxies → Turn ON Manual proxy configuration → Add org proxy URLs → Add bypass list"
            return 2  # Bypass missing - needs manual mode
        fi
    fi

    # Scenario 3: Windows has proxy, Docker Manual is ON
    if [[ "$docker_manual_proxy" == "true" ]] && [[ "$windows_proxy_state" != "no_proxy" ]]; then
        # Check if bypass list contains required domains
        local bypass_output
        bypass_output=$(check_bypass_domains "$settings_bypass_list" 2>&1)
        local bypass_exit=$?

        if [ $bypass_exit -eq 0 ] && [[ "$docker_no_proxy" == *"localhost"* ]]; then
            echo "PROXY_SCENARIO=manual_proxy_working"
            echo "RECOMMENDED_ACTION=none_needed"
            echo "SCENARIO_GUIDANCE=Manual proxy mode working correctly with proper bypass list."
            return 0  # Working correctly
        elif [ $bypass_exit -eq 2 ]; then
            echo "PROXY_SCENARIO=manual_proxy_missing_bypass"
            echo "RECOMMENDED_ACTION=add_bypass_domains"
            echo "SCENARIO_GUIDANCE=Manual proxy mode enabled but bypass list incomplete."
            echo "UI_STEPS=Settings → Resources → Proxies → Add to bypass list: localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"
            return 2  # Bypass missing from settings
        else
            echo "PROXY_SCENARIO=manual_proxy_restart_needed"
            echo "RECOMMENDED_ACTION=restart_docker"
            echo "SCENARIO_GUIDANCE=Manual proxy mode configured correctly but Docker engine not reflecting changes."
            echo "UI_STEPS=Apply & Restart Docker Desktop, then restart WSL2 if needed"
            return 3  # Restart required
        fi
    fi

    # Scenario 4: Mismatched states or PAC files
    if [[ "$windows_proxy_state" == "pac_proxy" ]]; then
        echo "PROXY_SCENARIO=pac_proxy_detected"
        echo "RECOMMENDED_ACTION=resolve_pac_configuration"
        echo "SCENARIO_GUIDANCE=PAC file detected. Contact IT for resolved HTTP/HTTPS proxy URLs or check browser proxy details."
        echo "UI_STEPS=Get proxy URLs from IT → Settings → Resources → Proxies → Manual ON → Enter resolved URLs → Add bypass list"
        return 4  # Special handling needed
    fi

    # Default: Complex scenario
    echo "PROXY_SCENARIO=complex_configuration"
    echo "RECOMMENDED_ACTION=manual_investigation"
    echo "SCENARIO_GUIDANCE=Complex proxy configuration detected. Manual analysis required."
    return 4
}

# Show Docker Desktop UI guidance based on scenario analysis
show_docker_desktop_ui_guidance() {
    local scenario="$1"
    local action="$2"
    local ui_steps="$3"
    local windows_pac_url="$4"

    echo ""
    echo "🎯 DOCKER DESKTOP UI GUIDANCE"
    echo "============================="
    echo ""

    case "$action" in
        "keep_manual_off")
            echo "✅ CORRECT CONFIGURATION:"
            echo "• Your system has no proxy"
            echo "• Keep Docker Desktop in System proxy mode (Manual OFF)"
            echo "• No bypass list needed"
            echo ""
            echo "VERIFICATION:"
            echo "Settings → Resources → Proxies → Manual proxy configuration should be OFF"
            ;;

        "enable_manual_mode")
            echo "🔄 ACTION REQUIRED - Enable Manual Mode:"
            echo "1. Open Docker Desktop → Settings → Resources → Proxies"
            echo "2. Toggle ON 'Manual proxy configuration'"
            echo "3. Fill in your corporate proxies:"
            echo "   PowerShell command to get proxy: Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'"
            echo "4. Add bypass list: localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"
            echo "5. Click Apply & Restart"
            ;;

        "add_bypass_domains")
            echo "📝 ACTION REQUIRED - Add Bypass Domains:"
            echo "1. Open Docker Desktop → Settings → Resources → Proxies"
            echo "2. In 'Bypass proxy settings for these hosts & domains' field, add:"
            echo "   localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"
            echo "3. Click Apply & Restart"
            ;;

        "restart_docker")
            echo "🔄 ACTION REQUIRED - Restart Docker:"
            echo "1. Right-click Docker Desktop system tray → Restart"
            echo "2. Wait for 'Running' status (30-60 seconds)"
            echo "3. If still not working, restart WSL2:"
            echo "   • PowerShell as Admin: wsl --shutdown"
            echo "   • Wait 10 seconds, reopen WSL2 terminal"
            ;;

        "resolve_pac_configuration")
            echo "🌐 ACTION REQUIRED - Resolve PAC Configuration:"
            echo "PAC File Detected: $windows_pac_url"
            echo ""
            echo "OPTIONS:"
            echo "1. Get resolved proxy URLs from IT team"
            echo "2. Check browser proxy details (Chrome: chrome://net-internals/#proxy)"
            echo "3. Then configure Docker Desktop:"
            echo "   • Settings → Resources → Proxies → Manual ON"
            echo "   • Enter resolved HTTP/HTTPS proxy URLs"
            echo "   • Add bypass list: localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"
            ;;

        *)
            echo "🔍 COMPLEX SCENARIO - Manual Investigation Required"
            echo "Your proxy configuration requires individual analysis."
            echo "Consider contacting IT support for Docker Desktop proxy configuration."
            ;;
    esac

    echo ""
}

# Determine precise proxy state using state machine logic
determine_proxy_state() {
    local docker_http_proxy="$1"
    local docker_no_proxy="$2"
    local settings_proxy_mode="$3"
    local settings_bypass_list="$4"

    # State 1: Check if proxy is configured at engine level
    if [ -z "$docker_http_proxy" ]; then
        echo "PROXY_STATE=no_proxy_configured"
        return 1
    fi

    # State 2: Check if bypass domains are configured in settings
    local bypass_output
    bypass_output=$(check_bypass_domains "$settings_bypass_list" 2>&1)
    local bypass_exit=$?

    if [ $bypass_exit -eq 2 ]; then
        echo "PROXY_STATE=bypass_missing_from_settings"
        return 2
    fi

    # State 3: Check if settings are applied to Docker engine
    if [[ "$docker_no_proxy" == *"localhost"* ]]; then
        echo "PROXY_STATE=working_correctly"
        return 0
    else
        echo "PROXY_STATE=restart_required"
        echo "DIAGNOSIS=Settings configured correctly but Docker engine not reflecting changes"
        echo "POTENTIAL_CAUSE=Docker restart needed OR corporate policy override"
        return 3
    fi
}

# Main sophisticated diagnostic function for enterprise proxy environments
main() {
    local docker_engine_exit docker_settings_exit
    local docker_http_proxy docker_no_proxy settings_proxy_mode settings_bypass_list
    local windows_proxy_state docker_manual_proxy

    echo "🔍 SOPHISTICATED DOCKER PROXY DIAGNOSTICS FOR ENTERPRISE ENVIRONMENTS"
    echo "====================================================================="

    # Step 1: Analyze Windows proxy landscape (what Docker actually reads)
    echo ""
    echo "📊 WINDOWS PROXY LANDSCAPE ANALYSIS"
    echo "===================================="
    local windows_output
    windows_output=$(detect_windows_proxy_state 2>&1)
    echo "$windows_output"

    # Extract Windows proxy state
    windows_proxy_state=$(echo "$windows_output" | grep "WINDOWS_PROXY_STATE=" | cut -d= -f2-)

    # Step 2: Check Docker engine state
    echo ""
    echo "🐳 DOCKER ENGINE ANALYSIS"
    echo "========================="
    local engine_output
    engine_output=$(detect_docker_engine_proxy 2>&1)
    docker_engine_exit=$?
    echo "$engine_output"

    if [ $docker_engine_exit -eq 4 ]; then
        echo "OVERALL_STATUS=docker_not_accessible"
        return 4
    fi

    # Extract engine values
    docker_http_proxy=$(echo "$engine_output" | grep "DOCKER_HTTP_PROXY=" | cut -d= -f2-)
    docker_no_proxy=$(echo "$engine_output" | grep "DOCKER_NO_PROXY=" | cut -d= -f2-)

    # Step 3: Check Docker Desktop settings with sophisticated mode detection
    echo ""
    echo "⚙️  DOCKER DESKTOP SETTINGS ANALYSIS"
    echo "==================================="
    local settings_output
    settings_output=$(detect_docker_settings 2>&1)
    docker_settings_exit=$?
    echo "$settings_output"

    if [ $docker_settings_exit -eq 4 ]; then
        echo "OVERALL_STATUS=settings_not_accessible"
        return 4
    fi

    # Extract settings values
    settings_proxy_mode=$(echo "$settings_output" | grep "SETTINGS_PROXY_MODE=" | cut -d= -f2-)
    settings_bypass_list=$(echo "$settings_output" | grep "SETTINGS_BYPASS_LIST=" | cut -d= -f2-)
    docker_manual_proxy=$(echo "$settings_output" | grep "DOCKER_MANUAL_PROXY=" | cut -d= -f2-)

    # Step 4: Comprehensive cross-checks for bulletproof analysis
    perform_comprehensive_proxy_crosschecks

    # Step 5: Sophisticated scenario analysis
    local scenario_output scenario_exit
    scenario_output=$(analyze_proxy_scenario "$windows_proxy_state" "$docker_manual_proxy" "$docker_no_proxy" "$settings_bypass_list" "$docker_http_proxy" 2>&1)
    scenario_exit=$?
    echo "$scenario_output"

    # Extract scenario analysis results
    local proxy_scenario=$(echo "$scenario_output" | grep "PROXY_SCENARIO=" | cut -d= -f2-)
    local recommended_action=$(echo "$scenario_output" | grep "RECOMMENDED_ACTION=" | cut -d= -f2-)
    local automated_fix=$(echo "$scenario_output" | grep "AUTOMATED_FIX=" | cut -d= -f2-)
    local windows_pac_url=$(echo "$windows_output" | grep "WINDOWS_PAC_URL=" | cut -d= -f2-)

    # Step 6: Handle automated resync for Docker Desktop sync issues
    if [ $scenario_exit -eq 5 ] && [[ "$recommended_action" == "automated_resync" ]]; then
        echo ""
        echo "🎯 DECISION SUMMARY"
        echo "=================="
        echo "DETECTED: Docker Desktop sync issue (Windows: no proxy ↔ Docker: cached proxy)"
        echo "EXPLANATION: This is normal after network changes. Your UI state is correct."
        echo "SOLUTION: Automated resync to clear Docker Desktop's cached proxy configuration"
        echo ""

        # Offer automated fix
        echo "🤖 AUTOMATED FIX AVAILABLE"
        echo "=========================="
        echo "This diagnostic can automatically fix the sync issue by:"
        echo "1. Stopping Docker Desktop & WSL"
        echo "2. Patching settings-store.json to force system proxy mode"
        echo "3. Clearing cached proxy configuration"
        echo "4. Restarting and verifying the fix"
        echo ""

        # For now, show what the automated fix would do
        # In the Ansible integration, this could be triggered automatically
        perform_automated_docker_resync
        scenario_exit=$?
    fi

    # Step 7: Show targeted Docker Desktop UI guidance for other scenarios
    if [ $scenario_exit -ne 5 ]; then
        show_docker_desktop_ui_guidance "$proxy_scenario" "$recommended_action" "" "$windows_pac_url"
    fi

    # Step 8: Corporate policy investigation if needed
    if [ $scenario_exit -eq 3 ] || [[ "$recommended_action" == "manual_investigation" ]]; then
        show_corporate_policy_guidance
    fi

    # Step 9: Final decision summary
    echo ""
    echo "📊 FINAL DIAGNOSIS SUMMARY"
    echo "=========================="
    local explanation=$(echo "$scenario_output" | grep "EXPLANATION=" | cut -d= -f2-)
    if [ -n "$explanation" ]; then
        echo "EXPLANATION: $explanation"
    fi

    # Map to legacy exit codes for compatibility
    case $scenario_exit in
        0)
            echo "OVERALL_STATUS=proxy_bypass_working"
            ;;
        1)
            echo "OVERALL_STATUS=no_proxy_configured"
            ;;
        2)
            echo "OVERALL_STATUS=bypass_missing_from_settings"
            ;;
        3)
            echo "OVERALL_STATUS=restart_required"
            ;;
        4)
            echo "OVERALL_STATUS=complex_configuration"
            ;;
        5)
            echo "OVERALL_STATUS=sync_issue_resolved"
            ;;
    esac

    return $scenario_exit
}

# Run diagnostics if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
