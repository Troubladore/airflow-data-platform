# Windows User Context Diagnostics
# Helps diagnose username/user context issues in certificate setup

Write-Host "Windows User Context Diagnostics" -ForegroundColor Blue
Write-Host "================================" -ForegroundColor Blue
Write-Host ""

# Check Windows user context
Write-Host "WINDOWS USER CONTEXT:" -ForegroundColor Yellow
Write-Host "Current Windows user: $env:USERNAME" -ForegroundColor Green
Write-Host "Current domain/computer: $env:USERDOMAIN" -ForegroundColor Green
Write-Host "User profile path: $env:USERPROFILE" -ForegroundColor Green
Write-Host "Temp directory: $env:TEMP" -ForegroundColor Green
Write-Host ""

# Check if mkcert is available and its context
Write-Host "MKCERT CONTEXT:" -ForegroundColor Yellow
try {
    $mkcertPath = Get-Command mkcert -ErrorAction Stop
    Write-Host "mkcert found at: $($mkcertPath.Source)" -ForegroundColor Green

    # Get CAROOT
    $caroot = mkcert -CAROOT 2>$null
    Write-Host "CAROOT directory: $caroot" -ForegroundColor Green

    # Check if CAROOT exists and show contents
    if (Test-Path $caroot) {
        Write-Host "CAROOT contents:" -ForegroundColor Green
        Get-ChildItem $caroot | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor Gray
        }

        # Check CA certificate details
        $rootCert = Get-ChildItem $caroot -Filter "rootCA.pem" -ErrorAction SilentlyContinue
        if ($rootCert) {
            try {
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($rootCert.FullName)
                Write-Host "CA Certificate Subject: $($cert.Subject)" -ForegroundColor Green
                Write-Host "CA Certificate Issuer: $($cert.Issuer)" -ForegroundColor Green
            } catch {
                Write-Host "Could not read CA certificate details" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "CAROOT directory does not exist yet" -ForegroundColor Yellow
    }

} catch {
    Write-Host "mkcert not found or not accessible" -ForegroundColor Red
}

Write-Host ""

# Check Windows certificate store for existing mkcert CAs
Write-Host "WINDOWS CERTIFICATE STORE:" -ForegroundColor Yellow
try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadOnly")

    $mkcertCerts = $store.Certificates | Where-Object { $_.Subject -like "*mkcert*" }

    if ($mkcertCerts.Count -gt 0) {
        Write-Host "Found $($mkcertCerts.Count) mkcert certificate(s) in Windows store:" -ForegroundColor Green
        foreach ($cert in $mkcertCerts) {
            Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
            Write-Host "  Issuer: $($cert.Issuer)" -ForegroundColor Gray
            Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
            Write-Host ""
        }
    } else {
        Write-Host "No mkcert certificates found in Windows certificate store" -ForegroundColor Yellow
    }

    $store.Close()
} catch {
    Write-Host "Could not access Windows certificate store: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "DIAGNOSIS COMPLETE" -ForegroundColor Blue
Write-Host "=================" -ForegroundColor Blue
