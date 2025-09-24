# Docker Desktop Proxy Bypass Configuration Utility
# Ensures *.localhost domains bypass corporate proxy settings
param(
    [switch]$Force,       # Skip confirmation prompts
    [switch]$RestartDocker # Automatically restart Docker Desktop
)

Write-Host "Docker Desktop Proxy Configuration Utility" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Required domains for platform development
$RequiredBypass = @(
    "localhost",
    "*.localhost",
    "127.0.0.1",
    "registry.localhost",
    "traefik.localhost",
    "airflow.localhost"
)

# Find Docker Desktop settings
$PossiblePaths = @(
    "$env:APPDATA\Docker\settings.json",
    "$env:LOCALAPPDATA\Docker\settings.json",
    "$env:USERPROFILE\AppData\Roaming\Docker\settings.json"
)

$SettingsPath = $null
foreach ($Path in $PossiblePaths) {
    if (Test-Path $Path) {
        $SettingsPath = $Path
        Write-Host "Found Docker settings: $Path" -ForegroundColor Green
        break
    }
}

if (-not $SettingsPath) {
    Write-Host "Docker Desktop settings.json not found" -ForegroundColor Red
    Write-Host "   Searched paths:" -ForegroundColor Gray
    $PossiblePaths | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    exit 1
}

# Check if Docker Desktop is running
$DockerProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
if (-not $DockerProcess) {
    Write-Host "Docker Desktop is not running" -ForegroundColor Yellow
    Write-Host "   Please start Docker Desktop before running this utility" -ForegroundColor Gray
    exit 1
}

try {
    # Read current settings
    Write-Host "Reading Docker Desktop configuration..." -ForegroundColor Blue
    $Settings = Get-Content $SettingsPath | ConvertFrom-Json

    # Check current proxy configuration
    $ProxyMode = $Settings.proxyHttpMode
    $CurrentBypass = $Settings.overrideProxyExclude -split ',' | ForEach-Object { $_.Trim() }

    Write-Host "Current Configuration:" -ForegroundColor White
    Write-Host "   Proxy Mode: $ProxyMode" -ForegroundColor Gray
    Write-Host "   Current Bypass List: $($Settings.overrideProxyExclude)" -ForegroundColor Gray

    # Check if proxy is being used
    if ($ProxyMode -ne "system" -and $ProxyMode -ne "manual") {
        Write-Host "Docker is not using proxy - no bypass needed" -ForegroundColor Green
        exit 0
    }

    # Check if all required domains are in bypass list
    $MissingDomains = $RequiredBypass | Where-Object { $_ -notin $CurrentBypass }

    if ($MissingDomains.Count -eq 0) {
        Write-Host "All required domains are in proxy bypass list" -ForegroundColor Green

        # Verify Docker engine settings
        Write-Host "Verifying Docker engine proxy settings..." -ForegroundColor Blue
        $DockerInfo = docker info --format "{{.NoProxy}}" 2>$null

        if ($DockerInfo -match "localhost") {
            Write-Host "Docker engine proxy bypass is working correctly" -ForegroundColor Green
            exit 0
        } else {
            Write-Host "⚠️  Docker engine proxy bypass not reflecting settings" -ForegroundColor Yellow
            Write-Host "   Settings file: *.localhost configured" -ForegroundColor Gray
            Write-Host "   Docker engine: $DockerInfo" -ForegroundColor Gray
            Write-Host "   Docker Desktop restart may be needed" -ForegroundColor Gray
        }
    } else {
        Write-Host "Missing domains in proxy bypass:" -ForegroundColor Red
        $MissingDomains | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
    }

    # Update bypass list if needed
    if ($MissingDomains.Count -gt 0) {
        Write-Host "🔧 Updating proxy bypass configuration..." -ForegroundColor Yellow

        # Backup current settings
        $BackupPath = "$SettingsPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $SettingsPath $BackupPath
        Write-Host "📁 Backup created: $BackupPath" -ForegroundColor Gray

        # Merge required domains
        $AllBypass = ($CurrentBypass + $RequiredBypass) | Sort-Object -Unique
        $Settings.overrideProxyExclude = $AllBypass -join ','

        # Save updated settings
        $Settings | ConvertTo-Json -Depth 32 | Out-File $SettingsPath -Encoding UTF8
        Write-Host "✅ Updated proxy bypass configuration" -ForegroundColor Green
    }

    # Check if restart is needed
    $RestartNeeded = ($MissingDomains.Count -gt 0) -or ($DockerInfo -notmatch "localhost")

    if ($RestartNeeded) {
        Write-Host ""
        Write-Host "🔄 Docker Desktop restart required for changes to take effect" -ForegroundColor Yellow

        if ($RestartDocker) {
            Write-Host "🔄 Restarting Docker Desktop..." -ForegroundColor Blue

            # Stop Docker Desktop
            Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Start Docker Desktop
            $DockerPath = Get-ChildItem -Path "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
            if ($DockerPath) {
                Start-Process -FilePath $DockerPath.FullName
                Write-Host "✅ Docker Desktop restart initiated" -ForegroundColor Green
                Write-Host "   Please wait for Docker to fully start before testing" -ForegroundColor Gray
            } else {
                Write-Host "❌ Could not find Docker Desktop executable" -ForegroundColor Red
                $RestartDocker = $false
            }
        }

        if (-not $RestartDocker) {
            if (-not $Force) {
                $Response = Read-Host "Restart Docker Desktop now? (y/N)"
                if ($Response -eq 'y' -or $Response -eq 'Y') {
                    $RestartDocker = $true
                }
            }

            if (-not $RestartDocker) {
                Write-Host ""
                Write-Host "⚠️  Manual restart required:" -ForegroundColor Yellow
                Write-Host "   1. Right-click Docker Desktop system tray icon" -ForegroundColor Gray
                Write-Host "   2. Select 'Restart'" -ForegroundColor Gray
                Write-Host "   3. Wait for Docker to fully restart" -ForegroundColor Gray
                Write-Host "   4. Test: docker info --format '{{.NoProxy}}'" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "✅ No restart needed - configuration is current" -ForegroundColor Green
    }

} catch {
    Write-Host "❌ Error configuring Docker proxy settings: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Docker proxy configuration complete!" -ForegroundColor Green
