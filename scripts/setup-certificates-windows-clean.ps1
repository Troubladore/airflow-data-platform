param()

Write-Host "Windows Certificate Setup Script" -ForegroundColor Blue
Write-Host "===================================" -ForegroundColor Blue
Write-Host ""

# Check if mkcert is installed
Write-Host "Step 1: Checking mkcert installation..." -ForegroundColor Yellow

try {
    $mkcertPath = Get-Command mkcert -ErrorAction Stop
    Write-Host "mkcert is installed at: $($mkcertPath.Source)" -ForegroundColor Green
} catch {
    Write-Host "mkcert is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install mkcert first:" -ForegroundColor Yellow
    Write-Host "  Option 1: scoop install mkcert" -ForegroundColor Cyan
    Write-Host "  Option 2: choco install mkcert" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# Install CA
Write-Host ""
Write-Host "Step 2: Installing mkcert CA..." -ForegroundColor Yellow
mkcert -uninstall 2>$null
mkcert -install

if ($LASTEXITCODE -eq 0) {
    Write-Host "CA installed successfully" -ForegroundColor Green
} else {
    Write-Host "CA installation failed" -ForegroundColor Red
    exit 1
}

# Get CAROOT and generate certificates
$CAROOT = mkcert -CAROOT
Write-Host "CA location: $CAROOT" -ForegroundColor Gray
Set-Location $CAROOT

Write-Host ""
Write-Host "Step 3: Generating certificates..." -ForegroundColor Yellow

# Generate wildcard certificate
mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key "*.localhost" localhost "traefik.localhost" "registry.localhost" "airflow.localhost" "*.airflow.localhost" 127.0.0.1 ::1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Wildcard certificate generated" -ForegroundColor Green
} else {
    Write-Host "Certificate generation failed" -ForegroundColor Red
    exit 1
}

# Generate registry certificate
mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key "registry.localhost" 127.0.0.1 ::1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Registry certificate generated" -ForegroundColor Green
} else {
    Write-Host "Registry certificate generation failed" -ForegroundColor Red
    exit 1
}

# Show results
Write-Host ""
Write-Host "Certificates created:" -ForegroundColor Green
Get-ChildItem $CAROOT -Filter "*.crt" | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Windows certificate setup complete\!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Return to WSL2" -ForegroundColor Cyan
Write-Host "2. Run: ansible-playbook ansible/site.yml" -ForegroundColor Cyan
