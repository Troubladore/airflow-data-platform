# Windows PowerShell script to set up mkcert and generate certificates
# Run this BEFORE running the WSL2 Ansible setup

Write-Host "🔐 Windows Certificate Setup Script" -ForegroundColor Blue
Write-Host "===================================" -ForegroundColor Blue
Write-Host ""

# Step 1: Check if mkcert is installed
Write-Host "Step 1: Checking mkcert installation..." -ForegroundColor Yellow

try {
    $mkcertPath = Get-Command mkcert -ErrorAction Stop
    Write-Host "✅ mkcert is installed at: $($mkcertPath.Source)" -ForegroundColor Green
} catch {
    Write-Host "❌ mkcert is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install mkcert first:" -ForegroundColor Yellow
    Write-Host "  Option 1: scoop install mkcert" -ForegroundColor Cyan
    Write-Host "  Option 2: choco install mkcert" -ForegroundColor Cyan
    Write-Host "  Option 3: Download from https://github.com/FiloSottile/mkcert/releases" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "After installing, run this script again." -ForegroundColor Yellow
    exit 1
}

# Step 2: Install CA (creates the directory)
Write-Host ""
Write-Host "Step 2: Installing mkcert CA..." -ForegroundColor Yellow

# First, clean up any old CAs
Write-Host "  Removing old CAs..." -ForegroundColor Gray
mkcert -uninstall 2>$null

# Install fresh CA
Write-Host "  Installing fresh CA..." -ForegroundColor Gray
mkcert -install

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ CA installed successfully" -ForegroundColor Green
} else {
    Write-Host "❌ CA installation failed" -ForegroundColor Red
    exit 1
}

# Step 3: Get CAROOT location
$CAROOT = mkcert -CAROOT
Write-Host "  CA location: $CAROOT" -ForegroundColor Gray

# Step 4: Navigate to mkcert directory
Write-Host ""
Write-Host "Step 3: Generating certificates with proper SANs..." -ForegroundColor Yellow

Set-Location $CAROOT

# Step 5: Generate certificates with all needed SANs
Write-Host "  Generating wildcard certificate..." -ForegroundColor Gray

mkcert -cert-file dev-localhost-wild.crt -key-file dev-localhost-wild.key `
    "*.localhost" localhost "traefik.localhost" "registry.localhost" `
    "airflow.localhost" "*.airflow.localhost" "*.customer.localhost" `
    127.0.0.1 ::1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Wildcard certificate generated" -ForegroundColor Green
} else {
    Write-Host "❌ Certificate generation failed" -ForegroundColor Red
    exit 1
}

Write-Host "  Generating registry certificate..." -ForegroundColor Gray

mkcert -cert-file dev-registry.localhost.crt -key-file dev-registry.localhost.key `
    "registry.localhost" 127.0.0.1 ::1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Registry certificate generated" -ForegroundColor Green
} else {
    Write-Host "❌ Registry certificate generation failed" -ForegroundColor Red
    exit 1
}

# Step 6: Display what was created
Write-Host ""
Write-Host "📜 Certificates created:" -ForegroundColor Green
Get-ChildItem $CAROOT -Filter "*.crt" | ForEach-Object {
    Write-Host "  ✅ $($_.Name)" -ForegroundColor Green
}
Get-ChildItem $CAROOT -Filter "*.key" | ForEach-Object {
    Write-Host "  ✅ $($_.Name)" -ForegroundColor Green
}

# Step 7: Instructions for WSL2
Write-Host ""
Write-Host "[SUCCESS] Windows certificate setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Return to WSL2" -ForegroundColor Cyan
Write-Host "2. Run: ansible-playbook ansible/site.yml" -ForegroundColor Cyan
Write-Host ""
Write-Host "The Ansible playbook will copy these certificates to WSL2 and configure trust." -ForegroundColor Gray
