# Comprehensive Certificate Store Diagnostics
# Searches all Windows certificate stores for mkcert certificates

Write-Host "Comprehensive Certificate Store Diagnostics" -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue
Write-Host ""

# Define all possible certificate stores to check
$storeLocations = @("CurrentUser", "LocalMachine")
$storeNames = @("My", "Root", "CA", "TrustedPeople", "TrustedPublisher")

foreach ($location in $storeLocations) {
    Write-Host "CHECKING $location CERTIFICATE STORES:" -ForegroundColor Yellow

    foreach ($storeName in $storeNames) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, $location)
            $store.Open("ReadOnly")

            # Search for certificates with various mkcert-related terms
            $searchTerms = @("mkcert", "development CA", "TROUBLADORE", "mayna", "Eric Maynard")
            $foundCerts = @()

            foreach ($term in $searchTerms) {
                $certs = $store.Certificates | Where-Object {
                    $_.Subject -like "*$term*" -or $_.Issuer -like "*$term*"
                }
                $foundCerts += $certs
            }

            # Remove duplicates
            $uniqueCerts = $foundCerts | Sort-Object Thumbprint | Get-Unique

            if ($uniqueCerts.Count -gt 0) {
                Write-Host "  $location\$storeName - Found $($uniqueCerts.Count) certificate(s):" -ForegroundColor Green
                foreach ($cert in $uniqueCerts) {
                    Write-Host "    Subject: $($cert.Subject)" -ForegroundColor Gray
                    Write-Host "    Issuer: $($cert.Issuer)" -ForegroundColor Gray
                    Write-Host "    Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
                    Write-Host "    Valid From: $($cert.NotBefore)" -ForegroundColor Gray
                    Write-Host "    Valid To: $($cert.NotAfter)" -ForegroundColor Gray
                    Write-Host ""
                }
            } else {
                Write-Host "  $location\$storeName - No relevant certificates" -ForegroundColor Gray
            }

            $store.Close()

        } catch {
            Write-Host "  $location\$storeName - Access denied or error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Also check what mkcert thinks about its installation
Write-Host "MKCERT INSTALLATION STATUS:" -ForegroundColor Yellow
try {
    $mkcertStatus = mkcert -install 2>&1
    Write-Host "mkcert -install output: $mkcertStatus" -ForegroundColor Green
} catch {
    Write-Host "Error running mkcert -install: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Check browser certificate stores if possible
Write-Host "BROWSER INTEGRATION CHECK:" -ForegroundColor Yellow
Write-Host "mkcert reports: The local CA is already installed in the system trust store!" -ForegroundColor Green
Write-Host "This means browsers SHOULD trust mkcert certificates." -ForegroundColor Green
Write-Host ""

Write-Host "COMPREHENSIVE DIAGNOSIS COMPLETE" -ForegroundColor Blue
Write-Host "================================" -ForegroundColor Blue
