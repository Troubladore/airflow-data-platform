# Safe mkcert CA Certificate Pollution Cleanup
# Removes duplicate mkcert CA certificates, keeping only the newest one
param(
    [switch]$Preview,    # Show what would be cleaned up (no changes)
    [switch]$Force       # Skip confirmation prompts
)

Write-Host "mkcert CA Certificate Cleanup" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# Open certificate store (CurrentUser only for safety)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "CurrentUser")
$store.Open('ReadOnly')

# Find mkcert certificates
$mkcertCerts = $store.Certificates | Where-Object {
    $_.Subject -like '*mkcert development CA*'
}

Write-Host "Analysis:"
Write-Host "   mkcert CA certificates found: $($mkcertCerts.Count)"

if ($mkcertCerts.Count -le 1) {
    Write-Host "   No cleanup needed" -ForegroundColor Green
    $store.Close()
    exit 0
}

# Find duplicates (same subject)
$grouped = $mkcertCerts | Group-Object Subject
$totalToRemove = 0
$cleanupPlan = @()

Write-Host ""
Write-Host "Pollution Analysis:" -ForegroundColor Yellow

foreach ($group in $grouped) {
    if ($group.Count -gt 1) {
        $certs = $group.Group | Sort-Object NotAfter -Descending
        $keepCert = $certs[0]  # Keep newest (latest expiration)
        $removeCerts = $certs[1..($certs.Count-1)]  # Remove older ones

        $subjectDisplay = if ($group.Name) { $group.Name.Substring(0, [Math]::Min(60, $group.Name.Length)) + "..." } else { "Unknown Subject" }
        Write-Host "   Subject: $subjectDisplay"
        $keepDate = if ($keepCert -and $keepCert.NotBefore) { $keepCert.NotBefore.ToString('yyyy-MM-dd HH:mm') } else { "Unknown" }
        Write-Host "KEEP: Created $keepDate" -ForegroundColor Green

        foreach ($cert in $removeCerts) {
            $removeDate = if ($cert -and $cert.NotBefore) { $cert.NotBefore.ToString('yyyy-MM-dd HH:mm') } else { "Unknown" }
            Write-Host "REMOVE: Created $removeDate" -ForegroundColor Red
            $cleanupPlan += $cert
            $totalToRemove++
        }
        Write-Host ""
    }
}

Write-Host "Summary:"
Write-Host "   Certificates to remove: $totalToRemove"
Write-Host "   Certificates to keep: $($mkcertCerts.Count - $totalToRemove)"

$store.Close()

if ($Preview) {
    Write-Host ""
    Write-Host "PREVIEW MODE - No changes made" -ForegroundColor Yellow
    Write-Host "   Run without -Preview to perform cleanup"
    exit 0
}

if ($totalToRemove -eq 0) {
    Write-Host "   No cleanup needed" -ForegroundColor Green
    exit 0
}

# Confirmation
if (-not $Force) {
    Write-Host ""
    Write-Host "Ready to remove $totalToRemove duplicate mkcert CA certificates" -ForegroundColor Yellow
    $response = Read-Host "Continue? (type yes)"
    if ($response -ne "yes") {
        Write-Host "Cancelled" -ForegroundColor Red
        exit 1
    }
}

# Perform cleanup
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Green

$store.Open("ReadWrite")
$removed = 0
$errors = 0

foreach ($cert in $cleanupPlan) {
    try {
        $store.Remove($cert)
        Write-Host "   ✅ Removed: $($cert.NotBefore.ToString("yyyy-MM-dd HH:mm"))" -ForegroundColor Green
        $removed++
    } catch {
        Write-Host "   ❌ Failed: $($cert.NotBefore.ToString("yyyy-MM-dd HH:mm"))" -ForegroundColor Red
        $errors++
    }
}

$store.Close()

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green
Write-Host "   Removed: $removed certificates"
if ($errors -gt 0) {
    Write-Host "   Errors: $errors certificates" -ForegroundColor Red
}
