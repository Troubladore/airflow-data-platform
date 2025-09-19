# Windows Prerequisites Setup Script
# Automates Windows-side setup as much as possible without admin complexity
#
# Usage: Run this in Windows PowerShell (regular user is fine for most tasks)
# .\scripts\win-prereqs.ps1

param(
    [switch]$SkipHostsFile,
    [switch]$Force
)

# Colors for output
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Blue }
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }

Write-Host @"
🪟 ================================================
   WINDOWS PREREQUISITES SETUP
   Astronomer Airflow Platform
================================================

This script automates Windows-side setup:
✅ Install Scoop package manager (if needed)
✅ Install mkcert via Scoop (non-admin)
✅ Install mkcert CA certificates (non-admin)
✅ Generate development certificates
✅ Update hosts file (requires admin)

"@ -ForegroundColor Cyan

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
    try {
        scoop install mkcert
        Write-Success "mkcert installed successfully"
    } catch {
        Write-Error "Failed to install mkcert: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Success "mkcert is already installed"
}

# Install mkcert CA (works for non-admin users)
Write-Info "Installing mkcert Certificate Authority..."
try {
    mkcert -install
    Write-Success "mkcert CA installed to user certificate store"
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
        mkcert -cert-file "dev-localhost-wild.crt" -key-file "dev-localhost-wild.key" "*.localhost" "localhost"
        Write-Success "Wildcard certificate generated"
    }

    # Generate specific certificate for registry.localhost
    if (-not (Test-Path "dev-registry.localhost.crt") -or $Force) {
        Write-Info "Generating certificate for registry.localhost..."
        mkcert -cert-file "dev-registry.localhost.crt" -key-file "dev-registry.localhost.key" "registry.localhost"
        Write-Success "Registry certificate generated"
    }

    Write-Success "Certificates generated in: $certDir"
    Write-Info "Certificate files:"
    Get-ChildItem $certDir -Filter "*.crt" | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }

} catch {
    Write-Error "Certificate generation failed: $($_.Exception.Message)"
    exit 1
}

# Hosts file management
if (-not $SkipHostsFile) {
    Write-Info "Checking hosts file entries..."
    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsEntries = @(
        "127.0.0.1 registry.localhost",
        "127.0.0.1 traefik.localhost"
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
            Write-Host "🪟 Run PowerShell as Administrator and execute:" -ForegroundColor Yellow
            Write-Host "Add-Content `"$hostsFile`" @(" -ForegroundColor Gray
            $missingEntries | ForEach-Object { Write-Host "  `"$_`"," -ForegroundColor Gray }
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

🎉 Windows Prerequisites Setup Complete!

✅ Scoop package manager ready
✅ mkcert installed and CA configured
✅ Development certificates generated
✅ Certificate location: $certDir

🐧 Next Steps (run in WSL2 Ubuntu terminal):
  cd /path/to/workstation-setup
  ansible-playbook -i ansible/inventory/local-dev.ini ansible/site.yml

🌐 Test endpoints after setup:
  https://traefik.localhost    (Traefik dashboard)
  https://registry.localhost   (Container registry)

"@ -ForegroundColor Green

Write-Info "Windows prerequisites complete! Continue with WSL2 setup..."
