# Windows Certificate Setup Script with Automated mkcert Installation
# This script combines mkcert installation and certificate generation in one flow
# Run this BEFORE running the WSL2 Ansible setup

param(
    [switch]$Force,
    [switch]$SkipInstallation
)

Write-Host "Windows Certificate Setup with mkcert Installation" -ForegroundColor Blue
Write-Host "====================================================" -ForegroundColor Blue
Write-Host ""

# Check if running as admin (for better error messages)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if ($isAdmin) {
    Write-Host "Running as Administrator - full automation available" -ForegroundColor Green
} else {
    Write-Host "Running as regular user - mkcert installation and CA setup work without admin" -ForegroundColor Green
}

# Step 1: Check if mkcert is installed, install if missing
Write-Host ""
Write-Host "Step 1: Checking mkcert installation..." -ForegroundColor Yellow

$mkcertInstalled = $false
try {
    $mkcertPath = Get-Command mkcert -ErrorAction Stop
    Write-Host "[OK] mkcert is installed at: $($mkcertPath.Source)" -ForegroundColor Green
    $mkcertInstalled = $true
} catch {
    Write-Host "[INSTALL] mkcert is not installed" -ForegroundColor Yellow

    if ($SkipInstallation) {
        Write-Host "[ERROR] mkcert not installed and -SkipInstallation specified" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install mkcert first:" -ForegroundColor Yellow
        Write-Host "  Option 1: scoop install mkcert" -ForegroundColor Cyan
        Write-Host "  Option 2: choco install mkcert" -ForegroundColor Cyan
        Write-Host "  Option 3: Download from https://github.com/FiloSottile/mkcert/releases" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
}

# Step 1.5: Install mkcert if not present
if (-not $mkcertInstalled) {
    Write-Host ""
    Write-Host "Step 1.5: Installing mkcert..." -ForegroundColor Yellow

    # Try Scoop first (cleanest method)
    Write-Host "  Attempting installation via Scoop..." -ForegroundColor Gray
    try {
        # Check if Scoop is installed
        $scoopInstalled = $false
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $scoopInstalled = $true
            Write-Host "  Scoop is available" -ForegroundColor Gray
        } else {
            Write-Host "  Installing Scoop first..." -ForegroundColor Gray
            # Install Scoop
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
                $scoopInstalled = $true
                Write-Host "  [OK] Scoop installed successfully" -ForegroundColor Green
            } catch {
                Write-Host "  [WARN] Scoop installation failed: $($_.Exception.Message)" -ForegroundColor Yellow
                $scoopInstalled = $false
            }
        }

        if ($scoopInstalled) {
            # Update Scoop and install mkcert
            try {
                Write-Host "  Updating Scoop buckets..." -ForegroundColor Gray
                scoop update 2>&1 | Out-Null

                # Add extras bucket if not present
                $buckets = scoop bucket list 2>&1
                if (-not ($buckets -match "extras")) {
                    Write-Host "  Adding extras bucket..." -ForegroundColor Gray
                    scoop bucket add extras 2>&1 | Out-Null
                }

                Write-Host "  Installing mkcert via Scoop..." -ForegroundColor Gray
                scoop install mkcert 2>&1 | Out-Null

                # Refresh PATH
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

                # Verify installation
                if (Get-Command mkcert -ErrorAction SilentlyContinue) {
                    Write-Host "  [OK] mkcert installed successfully via Scoop" -ForegroundColor Green
                    $mkcertInstalled = $true
                } else {
                    throw "mkcert not found after Scoop installation"
                }
            } catch {
                Write-Host "  [WARN] Scoop installation of mkcert failed: $($_.Exception.Message)" -ForegroundColor Yellow
                $mkcertInstalled = $false
            }
        }
    } catch {
        Write-Host "  [WARN] Scoop approach failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Fallback to direct download if Scoop failed
    if (-not $mkcertInstalled) {
        Write-Host "  Attempting direct download..." -ForegroundColor Gray
        try {
            $mkcertUrl = "https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-windows-amd64.exe"
            $mkcertPath = "$env:USERPROFILE\mkcert.exe"

            Write-Host "  Downloading mkcert from GitHub..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $mkcertUrl -OutFile $mkcertPath -UseBasicParsing

            if (Test-Path $mkcertPath) {
                # Add to PATH for this session
                $env:PATH = "$env:USERPROFILE;$env:PATH"
                Write-Host "  [OK] mkcert downloaded to: $mkcertPath" -ForegroundColor Green
                $mkcertInstalled = $true
            } else {
                throw "Download failed - file not found"
            }
        } catch {
            Write-Host "  [WARN] Direct download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Final check and error if all methods failed
    if (-not $mkcertInstalled) {
        Write-Host "[ERROR] All automated installation methods failed" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual installation required:" -ForegroundColor Yellow
        Write-Host "1. Visit: https://github.com/FiloSottile/mkcert/releases" -ForegroundColor Cyan
        Write-Host "2. Download: mkcert-v1.4.4-windows-amd64.exe" -ForegroundColor Cyan
        Write-Host "3. Rename to: mkcert.exe" -ForegroundColor Cyan
        Write-Host "4. Place in a folder in your PATH" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

# Step 2: Install CA (creates the directory)
Write-Host ""
Write-Host "Step 2: Installing mkcert CA..." -ForegroundColor Yellow

# First, clean up any old CAs if Force specified
if ($Force) {
    Write-Host "  Removing old CAs (Force mode)..." -ForegroundColor Gray
    mkcert -uninstall 2>$null
}

# Install fresh CA
Write-Host "  Installing CA..." -ForegroundColor Gray
$caResult = mkcert -install 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] CA installed successfully" -ForegroundColor Green
} else {
    Write-Host "[ERROR] CA installation failed" -ForegroundColor Red
    Write-Host "Output: $caResult" -ForegroundColor Gray
    exit 1
}

# Step 3: Get CAROOT location and navigate there
$CAROOT = mkcert -CAROOT
Write-Host "  CA location: $CAROOT" -ForegroundColor Gray

Write-Host ""
Write-Host "Step 3: Checking and generating certificates..." -ForegroundColor Yellow

Set-Location $CAROOT

# Step 4: Check if certificates exist and contain required domains
$regenerateWildcard = $false
$wildcardCertPath = Join-Path $CAROOT "dev-localhost-wild.crt"

if (Test-Path $wildcardCertPath) {
    Write-Host "  Checking existing wildcard certificate..." -ForegroundColor Gray

    # Define required domains
    $requiredDomains = @(
        "traefik.localhost",
        "registry.localhost",
        "registry-ui.localhost",
        "whoami.localhost",
        "airflow.localhost"
    )

    # Get certificate details using openssl if available, or certutil as fallback
    $certInfo = ""
    if (Get-Command openssl -ErrorAction SilentlyContinue) {
        $certInfo = & openssl x509 -in $wildcardCertPath -noout -text 2>$null
    } else {
        # Use certutil to check certificate (less detailed but available on Windows)
        $certInfo = & certutil -dump $wildcardCertPath 2>$null
    }

    # Check if all required domains are present
    $missingDomains = @()
    foreach ($domain in $requiredDomains) {
        if ($certInfo -notmatch $domain) {
            $missingDomains += $domain
        }
    }

    if ($missingDomains.Count -gt 0) {
        Write-Host "  Certificate missing domains: $($missingDomains -join ', ')" -ForegroundColor Yellow
        $regenerateWildcard = $true
    } else {
        Write-Host "[OK] Wildcard certificate exists with all required domains" -ForegroundColor Green
    }
} else {
    Write-Host "  Wildcard certificate not found" -ForegroundColor Yellow
    $regenerateWildcard = $true
}

# Only regenerate if needed or forced
if ($regenerateWildcard -or $Force) {
    if ($Force) {
        Write-Host "  Force regenerating wildcard certificate..." -ForegroundColor Yellow
    } else {
        Write-Host "  Generating wildcard certificate..." -ForegroundColor Yellow
    }

    $certResult = mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key `
        "*.localhost" localhost "traefik.localhost" "registry.localhost" "registry-ui.localhost" `
        "whoami.localhost" "airflow.localhost" "*.airflow.localhost" "*.customer.localhost" `
        127.0.0.1 ::1 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Wildcard certificate regenerated" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Certificate generation failed" -ForegroundColor Red
        Write-Host "Output: $certResult" -ForegroundColor Gray
        exit 1
    }
}

# Check and generate registry certificate if needed
$regenerateRegistry = $false
$registryCertPath = Join-Path $CAROOT "dev-registry.localhost.crt"

if (Test-Path $registryCertPath) {
    Write-Host "[OK] Registry certificate already exists" -ForegroundColor Green
} else {
    Write-Host "  Registry certificate not found" -ForegroundColor Yellow
    $regenerateRegistry = $true
}

if ($regenerateRegistry -or $Force) {
    if ($Force) {
        Write-Host "  Force regenerating registry certificate..." -ForegroundColor Yellow
    } else {
        Write-Host "  Generating registry certificate..." -ForegroundColor Yellow
    }

    $regResult = mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key `
        "registry.localhost" 127.0.0.1 ::1 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Registry certificate generated" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Registry certificate generation failed" -ForegroundColor Red
        Write-Host "Output: $regResult" -ForegroundColor Gray
        exit 1
    }
} else {
    Write-Host "  Skipping registry certificate generation (already exists)" -ForegroundColor Gray
}

# Step 5: Display what was created
Write-Host ""
Write-Host "Certificates created:" -ForegroundColor Green
Get-ChildItem $CAROOT -Filter "*.crt" | ForEach-Object {
    Write-Host "  [OK] $($_.Name)" -ForegroundColor Green
}
Get-ChildItem $CAROOT -Filter "*.key" | ForEach-Object {
    Write-Host "  [OK] $($_.Name)" -ForegroundColor Green
}

# Step 6: Success message and next steps
Write-Host ""
Write-Host "[SUCCESS] Windows certificate setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "What was accomplished:" -ForegroundColor Yellow
if (-not $mkcertInstalled) {
    Write-Host "1. [OK] mkcert installed automatically" -ForegroundColor Cyan
} else {
    Write-Host "1. [OK] mkcert was already installed" -ForegroundColor Cyan
}
Write-Host "2. [OK] mkcert CA installed to Windows certificate store" -ForegroundColor Cyan
Write-Host "3. [OK] Development certificates generated with proper SANs" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Return to WSL2" -ForegroundColor Cyan
Write-Host "2. Run: ansible-playbook ansible/site.yml" -ForegroundColor Cyan
Write-Host ""
Write-Host "The Ansible playbook will copy these certificates to WSL2 and configure trust." -ForegroundColor Gray
