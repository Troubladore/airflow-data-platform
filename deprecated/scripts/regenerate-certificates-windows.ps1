# Regenerate certificates in Windows with additional domains
# This script should be run from Windows PowerShell, not WSL2

Write-Host "Certificate Regeneration for Platform Services" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Get the mkcert directory
$MKCERT_DIR = "$env:LOCALAPPDATA\mkcert"
Write-Host "Working directory: $MKCERT_DIR" -ForegroundColor Yellow

# Change to mkcert directory
Set-Location $MKCERT_DIR

# Check if mkcert is available
try {
    $mkcertPath = (Get-Command mkcert -ErrorAction Stop).Source
    Write-Host "Found mkcert at: $mkcertPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR: mkcert not found in PATH" -ForegroundColor Red
    Write-Host "Please install mkcert first using: scoop install mkcert" -ForegroundColor Yellow
    exit 1
}

# Backup existing certificates
Write-Host ""
Write-Host "Backing up existing certificates..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (Test-Path "dev-localhost-wild.crt") {
    Copy-Item "dev-localhost-wild.crt" "backup_${timestamp}_dev-localhost-wild.crt"
    Copy-Item "dev-localhost-wild.key" "backup_${timestamp}_dev-localhost-wild.key"
    Write-Host "Backed up existing certificates with timestamp: $timestamp" -ForegroundColor Green
}

# Generate new wildcard certificate with all required domains
Write-Host ""
Write-Host "Generating new wildcard certificate..." -ForegroundColor Yellow
Write-Host "Including domains:" -ForegroundColor Yellow
Write-Host "  - *.localhost (wildcard)" -ForegroundColor Gray
Write-Host "  - localhost" -ForegroundColor Gray
Write-Host "  - traefik.localhost" -ForegroundColor Gray
Write-Host "  - registry.localhost" -ForegroundColor Gray
Write-Host "  - registry-ui.localhost" -ForegroundColor Gray
Write-Host "  - airflow.localhost" -ForegroundColor Gray
Write-Host "  - *.airflow.localhost" -ForegroundColor Gray
Write-Host "  - whoami.localhost" -ForegroundColor Gray
Write-Host "  - 127.0.0.1" -ForegroundColor Gray
Write-Host "  - ::1" -ForegroundColor Gray

# Generate the certificate
& mkcert `
    -cert-file dev-localhost-wild.crt `
    -key-file dev-localhost-wild.key `
    "*.localhost" `
    localhost `
    traefik.localhost `
    registry.localhost `
    registry-ui.localhost `
    airflow.localhost `
    "*.airflow.localhost" `
    whoami.localhost `
    127.0.0.1 `
    ::1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Certificate generated successfully!" -ForegroundColor Green

    # Also generate registry-specific cert if needed
    Write-Host ""
    Write-Host "Generating registry-specific certificate..." -ForegroundColor Yellow
    & mkcert `
        -cert-file dev-registry.localhost.crt `
        -key-file dev-registry.localhost.key `
        registry.localhost

    Write-Host ""
    Write-Host "SUCCESS: All certificates regenerated" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Return to WSL2" -ForegroundColor Yellow
    Write-Host "2. Run Component 3 to copy certificates to WSL2:" -ForegroundColor Yellow
    Write-Host "   ansible-playbook -i ansible/inventory/local-dev.ini ansible/orchestrators/setup-simple.yml --start-at-task 'Component 3'" -ForegroundColor Gray
    Write-Host "3. Restart Traefik to load new certificates:" -ForegroundColor Yellow
    Write-Host "   cd ~/platform-services/traefik && docker compose restart" -ForegroundColor Gray
    Write-Host ""
    Write-Host "The certificates now include registry-ui.localhost explicitly!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "ERROR: Failed to generate certificate" -ForegroundColor Red
    Write-Host "Check the error message above" -ForegroundColor Yellow
}
