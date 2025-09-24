# Windows-side Platform Teardown Script
# Run as Administrator for complete certificate cleanup
# Companion to the WSL2 teardown script

param(
    [switch]$WhatIf,     # Show what would be done without making changes
    [switch]$Force       # Skip confirmation prompts
)

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "Windows Platform Teardown Script" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator!" -ForegroundColor Yellow
    Write-Host "Some cleanup operations may fail due to insufficient permissions." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "For complete cleanup:" -ForegroundColor Yellow
    Write-Host "1. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Cyan
    Write-Host "2. Re-run this script" -ForegroundColor Cyan
    Write-Host ""

    if (-not $Force) {
        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            Write-Host "Cancelled" -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "Running with Administrator privileges" -ForegroundColor Green
}

Write-Host ""

# Get current machine info
$currentMachine = $env:COMPUTERNAME
Write-Host "Cleaning certificates for machine: $currentMachine" -ForegroundColor Yellow

# Function to clean certificate store with smart platform filtering
function Clean-CertificateStore {
    param(
        [string]$StoreName,
        [string]$StoreLocation,
        [string]$Description
    )

    Write-Host ""
    Write-Host "Cleaning $Description..." -ForegroundColor Yellow

    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)
        $store.Open('ReadOnly')

        # Find mkcert certificates for this machine (any user)
        # This handles cross-user scenarios like WSL2 vs Windows users
        $mkcertCerts = $store.Certificates | Where-Object {
            ($_.Subject -like '*mkcert development CA*' -or $_.Subject -like '*mkcert*CA*') -and
            (
                $_.Subject -like "*$currentMachine*" -or
                # Handle common variations and legacy patterns
                $_.Subject -like "*localhost*" -or
                $_.Subject -like "*$($currentMachine.ToLower())*"
            )
        }

        # Additional filtering: only include certificates that look like platform-generated ones
        # Exclude obviously corporate or third-party CAs
        $platformCerts = $mkcertCerts | Where-Object {
            # Include if it contains machine name or common development patterns
            $_.Subject -like "*$currentMachine*" -or
            $_.Subject -like "*@$currentMachine*" -or
            $_.Subject -like "*$currentMachine\\*" -or
            # Handle WSL2 usernames (common pattern: lowercase usernames)
            ($_.Subject -like "*@*" -and $_.Subject -like "*development CA*")
        }

        if ($platformCerts.Count -eq 0) {
            Write-Host "   No platform certificates found in $Description" -ForegroundColor Gray
            if ($mkcertCerts.Count -gt 0) {
                Write-Host "   (Found $($mkcertCerts.Count) mkcert cert(s) but none match this platform)" -ForegroundColor Gray
            }
            $store.Close()
            return $true
        }

        Write-Host "   Found $($platformCerts.Count) platform certificate(s):" -ForegroundColor White
        if ($mkcertCerts.Count -gt $platformCerts.Count) {
            Write-Host "   (Filtered out $($mkcertCerts.Count - $platformCerts.Count) non-platform mkcert cert(s))" -ForegroundColor Gray
        }

        foreach ($cert in $platformCerts) {
            $shortSubject = if ($cert.Subject.Length -gt 60) { $cert.Subject.Substring(0, 60) + "..." } else { $cert.Subject }
            $createDate = $cert.NotBefore.ToString('yyyy-MM-dd')

            if ($WhatIf) {
                Write-Host "   [PREVIEW] Would remove: $shortSubject (created $createDate)" -ForegroundColor Yellow
            } else {
                Write-Host "   Processing: $shortSubject (created $createDate)" -ForegroundColor White
            }
        }

        $store.Close()

        if (-not $WhatIf) {
            # Reopen for write access
            $store.Open('ReadWrite')
            $removed = 0
            $errors = 0

            foreach ($cert in $platformCerts) {
                try {
                    $store.Remove($cert)
                    $removed++
                    $shortSubject = if ($cert.Subject.Length -gt 60) { $cert.Subject.Substring(0, 60) + "..." } else { $cert.Subject }
                    Write-Host "   [OK] Removed: $shortSubject" -ForegroundColor Green
                } catch {
                    $errors++
                    $shortSubject = if ($cert.Subject.Length -gt 60) { $cert.Subject.Substring(0, 60) + "..." } else { $cert.Subject }
                    Write-Host "   [FAIL] Failed: $shortSubject" -ForegroundColor Red
                    Write-Host "          Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            $store.Close()

            Write-Host "   Results: $removed removed, $errors failed" -ForegroundColor $(if ($errors -eq 0) { "Green" } else { "Yellow" })
            return ($errors -eq 0)
        } else {
            return $true
        }

    } catch {
        Write-Host "   [ERROR] Could not access $Description" -ForegroundColor Red
        Write-Host "          $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Clean both CurrentUser and LocalMachine stores
$success = $true

$success = Clean-CertificateStore "Root" "CurrentUser" "Current User Certificate Store" -and $success

if ($isAdmin) {
    $success = Clean-CertificateStore "Root" "LocalMachine" "Local Machine Certificate Store" -and $success
} else {
    Write-Host ""
    Write-Host "Skipping Local Machine store (requires Administrator)" -ForegroundColor Yellow
}

# Clean up mkcert program data directory
# Show analysis before cleanup
if (-not $WhatIf -and -not $Force) {
    Write-Host ""
    Write-Host "ANALYSIS SUMMARY:" -ForegroundColor Cyan
    Write-Host "This will remove ALL mkcert certificates and data for this machine." -ForegroundColor Yellow
    Write-Host "Machine: $currentMachine" -ForegroundColor White
    Write-Host ""
    Write-Host "Impact:" -ForegroundColor Yellow
    Write-Host "- Removes certificates for ALL users on this machine" -ForegroundColor Red
    Write-Host "- Includes both Windows users and WSL2 users" -ForegroundColor Red
    Write-Host "- Requires fresh certificate generation after cleanup" -ForegroundColor Red
    Write-Host ""

    $continue = Read-Host "Continue with complete platform teardown? (type 'YES' to confirm)"
    if ($continue -ne "YES") {
        Write-Host "Cancelled - no changes made" -ForegroundColor Green
        exit 0
    }
}

Write-Host ""
Write-Host "Cleaning mkcert data directories..." -ForegroundColor Yellow

$mkcertDirs = @(
    "$env:LOCALAPPDATA\mkcert",
    "$env:APPDATA\mkcert"
)

foreach ($dir in $mkcertDirs) {
    if (Test-Path $dir) {
        if ($WhatIf) {
            Write-Host "   [PREVIEW] Would remove directory: $dir" -ForegroundColor Yellow
        } else {
            try {
                Remove-Item $dir -Recurse -Force -ErrorAction Stop
                Write-Host "   [OK] Removed directory: $dir" -ForegroundColor Green
            } catch {
                Write-Host "   [FAIL] Could not remove directory: $dir" -ForegroundColor Red
                Write-Host "          Error: $($_.Exception.Message)" -ForegroundColor Red
                $success = $false
            }
        }
    } else {
        Write-Host "   Directory not found: $dir" -ForegroundColor Gray
    }
}

# Summary
Write-Host ""
if ($WhatIf) {
    Write-Host "PREVIEW COMPLETE - No changes made" -ForegroundColor Cyan
    Write-Host "Run without -WhatIf to perform actual cleanup" -ForegroundColor Cyan
} elseif ($success) {
    Write-Host "Windows platform teardown completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Windows platform teardown completed with some issues" -ForegroundColor Yellow
    Write-Host "Check error messages above for details" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run WSL2 teardown: ./scripts/teardown.sh (option 3)" -ForegroundColor Cyan
Write-Host "2. Run fresh setup: ./scripts/setup-certificates-windows.ps1" -ForegroundColor Cyan
Write-Host "3. Deploy platform: ansible-playbook ansible/site.yml" -ForegroundColor Cyan

if (-not $success) {
    exit 1
}
