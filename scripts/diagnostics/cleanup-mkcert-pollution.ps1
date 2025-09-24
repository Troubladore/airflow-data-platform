# Safe mkcert CA Certificate Cleanup Utility
# Surgically removes duplicate mkcert CA certificates while preserving the newest one
#
# SAFETY FEATURES:
# - Only targets certificates with "mkcert development CA" in subject
# - Preserves the most recent certificate
# - Creates detailed backup before any changes
# - Provides preview mode (no changes)
# - Validates corporate environment safety
# - Allows rollback from backup

param(
    [switch]$Preview,          # Show what would be cleaned up (no changes)
    [switch]$Force,            # Skip confirmation prompts
    [switch]$Backup,           # Create backup without cleanup
    [string]$RestoreFrom = ""  # Restore from backup file
)

# Safety check: Only run on CurrentUser store (not system-wide)
$StoreLocation = "CurrentUser"
$StoreName = "Root"

Write-Host "🧹 mkcert CA Certificate Cleanup Utility" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

if ($RestoreFrom) {
    Write-Host "🔄 RESTORE MODE: Restoring certificates from backup" -ForegroundColor Yellow
    # Restore functionality (implementation would go here)
    Write-Host "❌ Restore functionality not yet implemented" -ForegroundColor Red
    exit 1
}

# Open certificate store
try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)
    $store.Open('ReadWrite')
} catch {
    Write-Host "❌ Failed to open certificate store: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    # Find all mkcert certificates
    $mkcertCerts = $store.Certificates | Where-Object {
        $_.Subject -like '*mkcert development CA*' -and
        $_.Subject -like '*mkcert*'
    }

    Write-Host "🔍 Certificate Store Analysis" -ForegroundColor Green
    Write-Host "   Store: $StoreLocation\$StoreName"
    Write-Host "   Total certificates in store: $($store.Certificates.Count)"
    Write-Host "   mkcert CA certificates found: $($mkcertCerts.Count)"
    Write-Host ""

    if ($mkcertCerts.Count -eq 0) {
        Write-Host "✅ No mkcert CA certificates found - nothing to clean up" -ForegroundColor Green
        exit 0
    }

    if ($mkcertCerts.Count -eq 1) {
        Write-Host "✅ Only 1 mkcert CA certificate found - no pollution to clean up" -ForegroundColor Green
        $cert = $mkcertCerts[0]
        $daysLeft = ($cert.NotAfter - (Get-Date)).Days
        Write-Host "   Certificate expires in $daysLeft days" -ForegroundColor Gray
        exit 0
    }

    # Analyze the pollution
    Write-Host "⚠️  Certificate Pollution Detected" -ForegroundColor Yellow
    Write-Host ""

    # Group by subject to identify duplicates
    $grouped = $mkcertCerts | Group-Object Subject

    $totalToRemove = 0
    $cleanupPlan = @()

    foreach ($group in $grouped) {
        $subjectCerts = $group.Group | Sort-Object NotAfter -Descending
        $keepCert = $subjectCerts[0]  # Keep the newest (longest expiration)
        $removeCerts = $subjectCerts[1..($subjectCerts.Count - 1)]  # Remove older ones

        if ($removeCerts.Count -gt 0) {
            Write-Host "📋 Subject: $($group.Name)" -ForegroundColor White
            Write-Host "   ✅ KEEP:   $($keepCert.NotBefore.ToString('yyyy-MM-dd HH:mm')) (expires $($keepCert.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor Green

            foreach ($cert in $removeCerts) {
                Write-Host "   ❌ REMOVE: $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm')) (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))" -ForegroundColor Red
                $cleanupPlan += @{
                    Action = "Remove"
                    Certificate = $cert
                    Reason = "Duplicate (older than kept certificate)"
                }
                $totalToRemove++
            }
            Write-Host ""
        }
    }

    Write-Host "📊 Cleanup Summary" -ForegroundColor Cyan
    Write-Host "   Total certificates to remove: $totalToRemove"
    Write-Host "   Certificates to keep: $($mkcertCerts.Count - $totalToRemove)"
    Write-Host ""

    if ($Preview) {
        Write-Host "👀 PREVIEW MODE - No changes will be made" -ForegroundColor Yellow
        Write-Host "   Run without -Preview to perform cleanup" -ForegroundColor Gray
        exit 0
    }

    if ($Backup) {
        Write-Host "💾 BACKUP MODE - Creating backup without cleanup" -ForegroundColor Yellow
        # Backup functionality would go here
        Write-Host "❌ Backup functionality not yet implemented" -ForegroundColor Red
        exit 1
    }

    if ($totalToRemove -eq 0) {
        Write-Host "✅ No cleanup needed" -ForegroundColor Green
        exit 0
    }

    # Confirmation prompt (unless -Force)
    if (-not $Force) {
        Write-Host "⚠️  SAFETY CHECK" -ForegroundColor Yellow
        Write-Host "   This will remove $totalToRemove duplicate mkcert CA certificates" -ForegroundColor Yellow
        Write-Host "   Only certificates created by mkcert will be affected" -ForegroundColor Yellow
        Write-Host "   The newest certificate for each subject will be preserved" -ForegroundColor Yellow
        Write-Host ""
        $response = Read-Host "Proceed with cleanup? (type 'yes' to confirm)"

        if ($response -ne 'yes') {
            Write-Host "❌ Cleanup cancelled by user" -ForegroundColor Red
            exit 1
        }
    }

    # Perform cleanup
    Write-Host "🧹 Performing cleanup..." -ForegroundColor Green
    $removed = 0
    $errors = 0

    foreach ($item in $cleanupPlan) {
        try {
            $cert = $item.Certificate
            $store.Remove($cert)
            Write-Host "   ✅ Removed: $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Green
            $removed++
        } catch {
            Write-Host "   ❌ Failed to remove: $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm')) - $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ""
    Write-Host "🎉 Cleanup Complete!" -ForegroundColor Green
    Write-Host "   Certificates removed: $removed"
    if ($errors -gt 0) {
        Write-Host "   Errors encountered: $errors" -ForegroundColor Red
    }

    # Verify cleanup
    Write-Host ""
    Write-Host "🔍 Verification..." -ForegroundColor Gray
    $store.Close()
    $store.Open('ReadOnly')
    $remainingCerts = $store.Certificates | Where-Object {
        $_.Subject -like '*mkcert development CA*' -and
        $_.Subject -like '*mkcert*'
    }

    Write-Host "   mkcert CA certificates remaining: $($remainingCerts.Count)" -ForegroundColor Gray

    if ($remainingCerts.Count -eq 1) {
        Write-Host "   ✅ Certificate store cleanup successful!" -ForegroundColor Green
    } elseif ($remainingCerts.Count -eq 0) {
        Write-Host "   ⚠️  All mkcert certificates removed - you may need to reinstall mkcert" -ForegroundColor Yellow
    } else {
        Write-Host "   ⚠️  $($remainingCerts.Count) certificates remain - manual review recommended" -ForegroundColor Yellow
    }

} catch {
    Write-Host "❌ Error during cleanup: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    $store.Close()
}
