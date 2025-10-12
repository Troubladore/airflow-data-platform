# Unified Docker Proxy Handler - Combines focused automation with comprehensive diagnostics
# Uses focused Test-FixDockerProxy for automation, comprehensive diagnostic for complex cases

param(
    [switch]$AutoFix,
    [switch]$DiagnosticMode,
    [switch]$DryRun
)

# Your focused automation function - complete implementation
function Test-FixDockerProxy {
    [CmdletBinding()]
    param(
        [switch]$FixCliConfig,
        [switch]$DryRun,
        [int]$SleepAfterRestartSec = 15
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $result = @{
        Verdict     = "Unknown"
        Remediation = "None"
        Notes       = @()
    }

    function Add-Note { param($m); $script:result.Notes += $m }

    # --- Gather facts ----------------------------------------------------------
    try {
        $hk = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop | Select-Object ProxyEnable, ProxyServer, AutoConfigURL
    } catch {
        $hk = $null; Add-Note "WinINET read failed: $($_.Exception.Message)"
    }

    $cliPath = Join-Path $HOME ".docker\config.json"
    $cliCfg  = $null
    if (Test-Path $cliPath) {
        try {
            $cliRaw = Get-Content $cliPath -Raw; $cliCfg = $cliRaw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Add-Note ".docker/config.json parse failed: $($_.Exception.Message)"
        }
    }

    $envVars = (Get-ChildItem Env: | Where-Object { $_.Name -match '^(HTTP|HTTPS|NO)_PROXY' }) | Select-Object Name,Value

    $sp = Join-Path $env:APPDATA "Docker\settings-store.json"
    $settings = $null
    if (Test-Path $sp) {
        try {
            $settings = (Get-Content $sp -Raw | ConvertFrom-Json)
        } catch {
            Add-Note "settings-store.json parse failed: $($_.Exception.Message)"
        }
    } else {
        Add-Note "settings-store.json not found at $sp"
    }

    $adminSettingsPath = "C:\ProgramData\DockerDesktop\admin-settings.json"
    $hasAdminPolicy = Test-Path $adminSettingsPath

    $dockerInfo = ""
    try {
        $dockerInfo = (docker info 2>$null)
    } catch {
        Add-Note "docker info not available (Desktop not started?)"
    }

    $rx = '^\s*(HTTP|HTTPS)\s*Proxy\s*:\s*(.+)'
    $httpProxy  = ($dockerInfo | Select-String -Pattern $rx -AllMatches).Matches | Where-Object { $_.Groups[1].Value -eq 'HTTP' } | ForEach-Object { $_.Groups[2].Value.Trim() } | Select-Object -First 1
    $httpsProxy = ($dockerInfo | Select-String -Pattern $rx -AllMatches).Matches | Where-Object { $_.Groups[1].Value -eq 'HTTPS' } | ForEach-Object { $_.Groups[2].Value.Trim() } | Select-Object -First 1
    $noProxy    = (($dockerInfo | Select-String -Pattern 'No\s*Proxy\s*:\s*(.*)').Matches | ForEach-Object { $_.Groups[1].Value.Trim() }) -join ','

    # --- Early exits / precedence ---------------------------------------------
    if ($hasAdminPolicy) {
        $result.Verdict     = "PolicyEnforced"
        $result.Remediation = "None (requires admin to change $adminSettingsPath)"
        Add-Note "Admin policy present: $adminSettingsPath - local edits may be overridden."
        return $result
    }

    if ($cliCfg -and $cliCfg.proxies) {
        $result.Verdict = "CLIConfigProxy"
        if ($FixCliConfig -and -not $DryRun) {
            try {
                Copy-Item $cliPath "$cliPath.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction Stop
                $cliCfg.PSObject.Properties.Remove('proxies')
                $cliCfg | ConvertTo-Json -Depth 10 | Set-Content $cliPath -Encoding UTF8
                $result.Remediation = "Removed 'proxies' from .docker\config.json (backup created)."
            } catch {
                $result.Remediation = "Suggested removing 'proxies' from .docker\config.json (backup failed: $($_.Exception.Message))"
            }
        } else {
            $result.Remediation = "Suggest removing 'proxies' from .docker\config.json (run with -FixCliConfig to auto-fix)."
        }
        Add-Note ".docker/config.json proxies detected."
        return $result
    }

    if ($envVars.Count -gt 0) {
        $result.Verdict     = "EnvProxy"
        $result.Remediation = "Clear HTTP(S)_PROXY/NO_PROXY from your user/system environment and restart shells."
        Add-Note ("Env vars: " + ($envVars | ForEach-Object { "$($_.Name)=$($_.Value)" } -join "; "))
        return $result
    }

    # --- Desktop desync detection ---------------------------------------------
    $winHasProxy = $hk -and ( ($hk.ProxyEnable -eq 1) -or ([string]::IsNullOrWhiteSpace($hk.AutoConfigURL) -eq $false) )
    $desktopSystemMode = $settings -and ($settings.UseSystemProxy -eq $true)
    $engineShowsProxy  = [bool]($httpProxy) -or [bool]($httpsProxy)

    if ($desktopSystemMode -and -not $winHasProxy -and $engineShowsProxy) {
        $result.Verdict = "DesktopDesync"
        if ($DryRun) {
            $result.Remediation = "Would force UseSystemProxy=true and clear ProxySettings, restart Desktop."
            Add-Note "DryRun: not modifying files."
            return $result
        }

        # Try to fix: stop Desktop, WSL, patch settings-store.json, restart, verify
        try {
            Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue | Out-Null
            wsl --shutdown | Out-Null
        } catch {
            Add-Note "Stop/WSL shutdown note: $($_.Exception.Message)"
        }

        try {
            if (-not (Test-Path $sp)) { throw "Cannot find $sp to patch." }
            Copy-Item $sp "$sp.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction Stop
            $j = Get-Content $sp -Raw | ConvertFrom-Json
            $j.UseSystemProxy = $true
            if ($j.PSObject.Properties.Name -contains 'ProxySettings') { $j.ProxySettings = $null }
            $j | ConvertTo-Json -Depth 12 | Set-Content $sp -Encoding UTF8
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" | Out-Null
            Start-Sleep -Seconds $SleepAfterRestartSec
            $dockerInfo = (docker info 2>$null)
            $engineShowsProxyAfter = [bool](($dockerInfo | Select-String -Pattern $rx -AllMatches).Matches)
            if ($engineShowsProxyAfter) {
                $result.Remediation = "Patched settings-store.json and restarted, but engine still shows proxy. Consider toggling UI ON->Apply->OFF->Apply."
            } else {
                $result.Remediation = "Patched settings-store.json and restarted. Engine no longer shows proxy (resynced)."
            }
        } catch {
            $result.Remediation = "Failed to patch settings-store.json: $($_.Exception.Message)"
        }

        return $result
    }

    # --- Otherwise: healthy or system-proxy-on purpose ------------------------
    if ($desktopSystemMode -and $winHasProxy) {
        $result.Verdict     = "SystemProxyInUse"
        $result.Remediation = "None (Desktop following Windows). If you need bypasses, switch Manual=ON and set No Proxy."
        return $result
    }

    if (-not $desktopSystemMode -and $settings -and $settings.ProxySettings) {
        $result.Verdict     = "ManualProxyInUse"
        $result.Remediation = "None. Edit Settings > Resources > Proxies to change HTTP/HTTPS/No Proxy."
        return $result
    }

    if (-not $engineShowsProxy) {
        $result.Verdict     = "HealthyNoProxy"
        $result.Remediation = "None."
    } else {
        $result.Verdict     = "ProxyFromUnknownSource"
        $result.Remediation = "Engine shows proxy, but sources unclear. Re-check CLI config, env vars, and admin policy."
    }

    return $result
}

# Wrapper function for installer integration
function Invoke-UnifiedDockerProxyHandler {
    Write-Host "Unified Docker Proxy Handler"
    Write-Host "=============================="

    if ($DiagnosticMode) {
        Write-Host "Running comprehensive diagnostic..."
        # Call comprehensive bash diagnostic via WSL
        wsl bash -c "/home/troubladore/repos/airflow-data-platform/scripts/diagnostics/docker-proxy-diagnostics.sh"
        return
    }

    Write-Host "Running focused automation check..."
    $result = Test-FixDockerProxy -DryRun:$DryRun -FixCliConfig:$AutoFix

    # Parse the verdict and remediation
    $verdict = $result.Verdict
    $remediation = $result.Remediation

    if ($verdict -eq "HealthyNoProxy") {
        Write-Host "Automation successful - no proxy configured"
        exit 0
    }
    elseif ($verdict -eq "DesktopDesync") {
        if ($remediation -like "*restarted. Engine no longer shows proxy*") {
            Write-Host "Automation successful - Docker Desktop resync completed"
            Write-Host "Remediation: $remediation"
            exit 0
        } else {
            Write-Host "Automation failed - Docker Desktop resync did not resolve the issue"
            Write-Host "Verdict: $verdict"
            Write-Host "Remediation: $remediation"
            exit 1
        }
    }
    elseif ($verdict -eq "PolicyEnforced" -or $verdict -eq "ProxyFromUnknownSource") {
        Write-Host "Complex scenario detected"
        if ($DryRun) {
            Write-Host "(DryRun mode: comprehensive diagnostic would run here)"
        } else {
            Write-Host "Running comprehensive diagnostic..."
            wsl bash -c "/home/troubladore/repos/airflow-data-platform/scripts/diagnostics/docker-proxy-diagnostics.sh"
        }
        exit 2
    }
    else {
        Write-Host "Standard configuration - may need manual adjustment"
        Write-Host "Verdict: $verdict"
        Write-Host "Remediation: $remediation"
        exit 1
    }
}

# Execute based on parameters
Invoke-UnifiedDockerProxyHandler
