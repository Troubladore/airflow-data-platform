# Windows Prerequisites Setup Script
# Automates Windows-side setup as much as possible without admin complexity
#
# Usage: Run this in Windows PowerShell (regular user is fine for most tasks)
# .\scripts\win-prereqs.ps1

param(
    [switch]$SkipHostsFile,
    [switch]$Force
)

# Colors for output (ASCII-safe for cross-platform execution)
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Blue }
function Write-Success { param($Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host @"
================================================
   WINDOWS PREREQUISITES SETUP
   Astronomer Airflow Platform
================================================

This script automates Windows-side setup:
* Install Scoop package manager (if needed)
* Install mkcert via Scoop (non-admin)
* Install mkcert CA certificates (non-admin)
* Generate development certificates
* Update hosts file (requires admin)

"@ -ForegroundColor Cyan

# Display PowerShell version information
Write-Info "PowerShell Version Information:"
Write-Info "  Version: $($PSVersionTable.PSVersion)"
Write-Info "  Edition: $($PSVersionTable.PSEdition)"
Write-Info "  Platform: $($PSVersionTable.Platform)"

# Check if running in Windows PowerShell vs PowerShell Core/7+
if ($PSVersionTable.PSEdition -eq "Desktop") {
    Write-Warning "Running in Windows PowerShell (Desktop Edition)"
    Write-Warning "For best compatibility, consider using PowerShell 7+ instead"
    Write-Info "PowerShell 7+ can be found as 'PowerShell 7' in Start Menu"
} else {
    Write-Success "Running in PowerShell $($PSVersionTable.PSEdition) - good for compatibility"
}

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Info "Running as Administrator - full automation available"
} else {
    Write-Info "Running as regular user - will provide admin guidance when needed"
}

# Install Scoop if not present
Write-Info "Checking for Scoop package manager..."
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Info "Installing Scoop package manager..."
    try {
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        Write-Success "Scoop installed successfully"
    } catch {
        Write-Error "Failed to install Scoop: $($_.Exception.Message)"
        Write-Warning "Manual installation: https://scoop.sh/#/"
        exit 1
    }
} else {
    Write-Success "Scoop is already installed"
}

# Install mkcert via Scoop
Write-Info "Checking for mkcert..."
if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
    Write-Info "Installing mkcert via Scoop..."

    # Check for previous failed installations and clean up
    $mkcertStatus = scoop status mkcert 2>&1
    if ($mkcertStatus -match "failed|broken|corrupt") {
        Write-Warning "Detected previous failed mkcert installation, cleaning up..."
        scoop uninstall mkcert 2>$null
        scoop cache rm mkcert 2>$null
    }

    try {
        # Debug Scoop environment
        Write-Info "Scoop debugging information:"
        Write-Info "  Scoop version: $(scoop --version 2>&1)"
        Write-Info "  Scoop root: $($env:SCOOP)"
        Write-Info "  User profile: $($env:USERPROFILE)"

        # Check if extras bucket is available (mkcert is in extras)
        Write-Info "Checking Scoop buckets..."
        $bucketsOutput = scoop bucket list 2>&1
        Write-Info "  Current buckets: $bucketsOutput"

        if (-not ($bucketsOutput -match "extras")) {
            Write-Info "Adding extras bucket for mkcert..."
            scoop bucket add extras 2>&1
        }

        # Try Scoop installation
        Write-Info "Attempting: scoop install mkcert"
        $scoopOutput = scoop install mkcert 2>&1
        Write-Info "Scoop install output: $scoopOutput"

        if ($LASTEXITCODE -ne 0) {
            throw "Scoop installation failed with exit code $LASTEXITCODE"
        }

        Write-Success "mkcert installation completed"

        # Refresh PATH environment variable to pick up newly installed tools
        Write-Info "Refreshing PATH environment..."
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

        # Verify mkcert is now available
        if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
            Write-Warning "mkcert not found in PATH after installation. Trying Scoop shims..."
            $scoopShims = "$env:USERPROFILE\scoop\shims"
            if (Test-Path "$scoopShims\mkcert.exe") {
                $env:PATH = "$scoopShims;$env:PATH"
                Write-Success "Added Scoop shims directory to PATH: $scoopShims"
            } else {
                throw "mkcert.exe not found in expected Scoop location: $scoopShims"
            }
        } else {
            Write-Success "mkcert is now available in PATH"
        }

    } catch {
        Write-Warning "Scoop installation failed: $($_.Exception.Message)"
        Write-Warning "Attempting alternative installation methods..."

        # Alternative 1: Try direct download
        Write-Info "Trying direct download from GitHub releases..."
        $mkcertUrl = "https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-windows-amd64.exe"
        $mkcertPath = "$env:USERPROFILE\mkcert.exe"

        try {
            Invoke-WebRequest -Uri $mkcertUrl -OutFile $mkcertPath -UseBasicParsing
            if (Test-Path $mkcertPath) {
                # Add to PATH for this session
                $env:PATH = "$env:USERPROFILE;$env:PATH"
                Write-Success "mkcert downloaded successfully to: $mkcertPath"
            } else {
                throw "Download failed - file not found"
            }
        } catch {
            Write-Warning "Direct download failed: $($_.Exception.Message)"

            # Alternative 2: Provide manual instructions
            Write-Error "Automated installation failed. Manual installation required."
            Write-Info ""
            Write-Info "Manual Installation Steps:"
            Write-Info "1. Download mkcert from: https://github.com/FiloSottile/mkcert/releases"
            Write-Info "2. Download 'mkcert-v1.4.4-windows-amd64.exe'"
            Write-Info "3. Rename it to 'mkcert.exe'"
            Write-Info "4. Place it in a folder in your PATH (e.g., C:\Windows\System32)"
            Write-Info "5. Or place in $env:USERPROFILE and add that to your PATH"
            Write-Info ""
            Write-Info "Then continue with certificate generation:"
            Write-Info "  mkcert -install"
            Write-Info "  mkdir `$env:LOCALAPPDATA\mkcert"
            Write-Info "  cd `$env:LOCALAPPDATA\mkcert"
            Write-Info "  mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key *.localhost localhost"
            Write-Info "  mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key registry.localhost"
            Write-Info ""
            exit 1
        }
    }
} else {
    Write-Success "mkcert is already installed"
}

# Verify mkcert is working before proceeding
Write-Info "Verifying mkcert installation..."
if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
    Write-Error "mkcert is still not available after installation attempts"
    Write-Warning "Manual steps required:"
    Write-Warning "1. Close this PowerShell window"
    Write-Warning "2. Open a new PowerShell window"
    Write-Warning "3. Run: mkcert -install"
    Write-Warning "4. Run: mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key *.localhost localhost"
    exit 1
}

# Install mkcert CA (works for non-admin users)
Write-Info "Installing mkcert Certificate Authority..."
try {
    $mkcertOutput = mkcert -install 2>&1
    Write-Success "mkcert CA installed to user certificate store"
    Write-Info "mkcert output: $mkcertOutput"
} catch {
    Write-Warning "mkcert CA installation had issues: $($_.Exception.Message)"
    Write-Info "This may be normal - continuing with certificate generation..."
}

# Generate certificates
Write-Info "Generating development certificates..."
$certDir = "$env:LOCALAPPDATA\mkcert"
if (-not (Test-Path $certDir)) {
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null
}

try {
    Set-Location $certDir

    # Generate wildcard certificate for *.localhost
    if (-not (Test-Path "dev-localhost-wild.crt") -or $Force) {
        Write-Info "Generating wildcard certificate for *.localhost..."
        $certOutput = mkcert -cert-file "dev-localhost-wild.crt" -key-file "dev-localhost-wild.key" "*.localhost" "localhost" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Wildcard certificate generated"
        } else {
            Write-Warning "Certificate generation may have had issues: $certOutput"
        }
    }

    # Generate specific certificate for registry.localhost
    if (-not (Test-Path "dev-registry.localhost.crt") -or $Force) {
        Write-Info "Generating certificate for registry.localhost..."
        $registryCertOutput = mkcert -cert-file "dev-registry.localhost.crt" -key-file "dev-registry.localhost.key" "registry.localhost" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Registry certificate generated"
        } else {
            Write-Warning "Registry certificate generation may have had issues: $registryCertOutput"
        }
    }

    Write-Success "Certificates generated in: $certDir"
    Write-Info "Certificate files:"
    Get-ChildItem $certDir -Filter "*.crt" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }

} catch {
    Write-Error "Certificate generation failed: $($_.Exception.Message)"
    exit 1
}

# Docker Desktop proxy configuration
Write-Info "Checking Docker Desktop proxy configuration..."
$dockerSettingsPath = "$env:APPDATA\Docker\settings.json"

if (Test-Path $dockerSettingsPath) {
    try {
        $dockerSettings = Get-Content $dockerSettingsPath -Raw | ConvertFrom-Json

        # Check if proxy mode is set and bypass list needs updating
        if ($dockerSettings.proxyHttpMode -eq "system" -or $dockerSettings.overrideProxyHttp -ne "") {
            $currentBypass = $dockerSettings.overrideProxyExclude
            $requiredDomains = "localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"

            if ($currentBypass -notmatch "\*\.localhost") {
                Write-Info "Docker Desktop uses proxy but *.localhost is not bypassed"
                Write-Info "Attempting to update Docker Desktop proxy bypass list..."

                # Backup current settings
                Copy-Item $dockerSettingsPath "$dockerSettingsPath.backup" -Force

                # Update the bypass list
                if ($currentBypass) {
                    # Append to existing bypass list
                    $dockerSettings.overrideProxyExclude = "$currentBypass,$requiredDomains"
                } else {
                    # Set new bypass list
                    $dockerSettings.overrideProxyExclude = $requiredDomains
                }

                # Save updated settings
                $dockerSettings | ConvertTo-Json -Depth 10 | Set-Content $dockerSettingsPath -Force
                Write-Success "Updated Docker Desktop proxy bypass list"
                Write-Warning "Docker Desktop needs to be restarted for changes to take effect"
                Write-Info "You can restart it manually or it will apply on next Docker Desktop start"
            } else {
                Write-Success "Docker Desktop proxy bypass already configured correctly"
            }
        } else {
            Write-Success "Docker Desktop not using proxy - no configuration needed"
        }
    } catch {
        Write-Warning "Could not update Docker Desktop settings automatically: $($_.Exception.Message)"
        Write-Info "Manual configuration may be needed:"
        Write-Info "  1. Open Docker Desktop"
        Write-Info "  2. Go to Settings -> Resources -> Proxies"
        Write-Info "  3. Add to bypass list: localhost,*.localhost,127.0.0.1,registry.localhost,traefik.localhost,airflow.localhost"
    }
} else {
    Write-Info "Docker Desktop settings not found - may not be installed or different location"
}

# Hosts file management
if (-not $SkipHostsFile) {
    Write-Info "Checking hosts file entries..."
    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsEntries = @(
        "127.0.0.1 registry.localhost",
        "127.0.0.1 traefik.localhost",
        "127.0.0.1 airflow.localhost"
    )

    $hostsContent = Get-Content $hostsFile -ErrorAction SilentlyContinue
    $missingEntries = @()

    foreach ($entry in $hostsEntries) {
        if ($hostsContent -notcontains $entry) {
            $missingEntries += $entry
        }
    }

    if ($missingEntries.Count -gt 0) {
        if ($isAdmin) {
            Write-Info "Adding entries to hosts file (admin mode)..."
            try {
                # Create backup
                Copy-Item $hostsFile "$hostsFile.backup" -Force

                # Add missing entries
                $hostsContent += $missingEntries
                $hostsContent | Set-Content $hostsFile -Force

                Write-Success "Hosts file updated with entries:"
                $missingEntries | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
            } catch {
                Write-Error "Failed to update hosts file: $($_.Exception.Message)"
                Write-Warning "You may need to add these entries manually"
            }
        } else {
            Write-Warning "Hosts file entries need to be added manually (requires admin):"
            Write-Host ""
            Write-Host "Run PowerShell as Administrator and execute:" -ForegroundColor Yellow
            Write-Host "Add-Content `"$hostsFile`" @(" -ForegroundColor Gray
            $missingEntries | ForEach-Object { Write-Host "  $_," -ForegroundColor Gray }
            Write-Host ")" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Or manually edit: $hostsFile" -ForegroundColor Gray
            Write-Host "Add these lines:" -ForegroundColor Gray
            $missingEntries | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
    } else {
        Write-Success "Hosts file entries are already present"
    }
}

# Final summary
Write-Host @"

Windows Prerequisites Setup Complete!

* Scoop package manager ready
* mkcert installed and CA configured
* Development certificates generated
* Certificate location: $certDir

Next Steps (run in WSL2 Ubuntu terminal):
  cd <<your_repo_folder>>/workstation-setup
  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml

Test endpoints after setup:
  https://traefik.localhost    (Traefik dashboard)
  https://registry.localhost   (Container registry)

"@ -ForegroundColor Green

Write-Info "Windows prerequisites complete! Continue with WSL2 setup..."
