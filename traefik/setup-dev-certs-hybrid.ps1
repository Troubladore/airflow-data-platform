# ============================================
# Secure Local Dev Certificate Setup
# For non-admin Windows users with WSL2
# ============================================

# 1. Setup secure directory structure (no admin needed)
$certBase = "$env:LOCALAPPDATA\mkcert"
$certPath = "$certBase\certs"
$docPath = "$certBase\docs"

Write-Host "Creating secure certificate directories..." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $certPath | Out-Null
New-Item -ItemType Directory -Force -Path $docPath | Out-Null

# 2. Navigate to cert directory
cd $certPath

# 3. Generate environment-specific certificates
Write-Host "`nGenerating development certificates..." -ForegroundColor Green
$env_prefix = "dev"
$timestamp = Get-Date -Format "yyyy-MM-dd"

# Generate registry certificate
Write-Host "  Creating registry.localhost certificate..." -ForegroundColor Gray
mkcert -cert-file "$env_prefix-registry.localhost.crt" -key-file "$env_prefix-registry.localhost.key" registry.localhost

# Generate wildcard certificate for single-level subdomains
Write-Host "  Creating wildcard localhost certificate..." -ForegroundColor Gray
mkcert -cert-file "$env_prefix-localhost-wild.crt" -key-file "$env_prefix-localhost-wild.key" localhost "*.localhost" "127.0.0.1" "::1"

# 4. Document certificates for verification
Write-Host "`nDocumenting certificate fingerprints..." -ForegroundColor Green
$fingerprintFile = "$docPath\cert-fingerprints-$timestamp.txt"

@"
========================================
Certificate Fingerprints
Generated: $timestamp
Environment: $env_prefix
========================================

"@ | Out-File -FilePath $fingerprintFile

# Get certificate details and fingerprints
Get-ChildItem "$certPath\$env_prefix-*.crt" | ForEach-Object {
    $certName = $_.Name
    Write-Host "  Processing $certName..." -ForegroundColor Gray
    
    # Get certificate info
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($_.FullName)
    
    # Add to documentation
    @"
Certificate: $certName
----------------------------------------
Subject: $($cert.Subject)
Issuer: $($cert.Issuer)
Valid From: $($cert.NotBefore)
Valid Until: $($cert.NotAfter)
Thumbprint: $($cert.Thumbprint)
"@ | Out-File -FilePath $fingerprintFile -Append
    
    # Add SHA256 hash
    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    "SHA256: $hash`n" | Out-File -FilePath $fingerprintFile -Append
}

Write-Host "`nFingerprints saved to: $fingerprintFile" -ForegroundColor Yellow

# 5. Create .gitignore for safety
$gitignorePath = "$certBase\.gitignore"
@"
# Local development certificates - NEVER COMMIT
*.key
*.crt
*.pem
*.p12
*.pfx
certs/
docs/cert-fingerprints-*.txt

# Keep docs folder but not sensitive content
!docs/README.md
"@ | Out-File -FilePath $gitignorePath -Encoding UTF8

# 6. Create README for documentation
$readmePath = "$docPath\README.md"
@"
# Local Development Certificates

## Overview
These certificates are for LOCAL DEVELOPMENT ONLY.
Generated: $timestamp
Environment Prefix: $env_prefix

## Security Notes
- **NEVER** commit certificates to version control
- These certs are only trusted on this machine
- Rotate every 6-12 months
- Keys have restricted permissions in WSL

## Certificate Purposes
- ``$env_prefix-registry.localhost.*``: Local Docker registry
- ``$env_prefix-localhost-wild.*``: Wildcard for all *.localhost services

## Supported Domains
The wildcard certificate covers:
- localhost
- *.localhost (single level subdomain)
  - registry.localhost
  - airflow-prod-high.localhost
  - airflow-dev-low.localhost
  - app-customer-staging.localhost
  - etc.

## Naming Convention
Use hyphens to separate multi-level concepts:
- Pattern: service-environment-priority.localhost
- Examples:
  - airflow-prod-high.localhost
  - app-customer-staging.localhost
  - api-internal-dev.localhost

## Verification
Check fingerprints against: cert-fingerprints-$timestamp.txt

## WSL Integration
Certificates are copied to: ~/.local/share/certs/
Docker secrets are linked to: ~/.docker/secrets/
"@ | Out-File -FilePath $readmePath -Encoding UTF8

# 7. Create WSL copy script (fixed version)
$wslScriptPath = "$certBase\copy-to-wsl.sh"
@'
#!/bin/bash
# Copy certificates from Windows to WSL with proper permissions

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Copying certificates to WSL...${NC}"

# Create directory structure
mkdir -p ~/.local/share/certs
mkdir -p ~/.docker/secrets

# Find the certificate directory
# Look for the certs folder in any user's mkcert directory
CERT_SOURCE=""
for user_dir in /mnt/c/Users/*/; do
    potential_cert_dir="${user_dir}AppData/Local/mkcert/certs"
    if [ -d "$potential_cert_dir" ]; then
        # Check if it actually contains dev-*.crt or dev-*.key files
        if ls "$potential_cert_dir"/dev-*.crt >/dev/null 2>&1 || ls "$potential_cert_dir"/dev-*.key >/dev/null 2>&1; then
            CERT_SOURCE="$potential_cert_dir"
            echo -e "${GREEN}Found certificates in: $CERT_SOURCE${NC}"
            break
        fi
    fi
done

# If not found, check if user specified it via environment variable
if [ -z "$CERT_SOURCE" ] && [ -n "${MKCERT_PATH:-}" ]; then
    if [ -d "$MKCERT_PATH" ]; then
        CERT_SOURCE="$MKCERT_PATH"
        echo -e "${GREEN}Using MKCERT_PATH: $CERT_SOURCE${NC}"
    fi
fi

# If still not found, error out with helpful message
if [ -z "$CERT_SOURCE" ]; then
    echo -e "${RED}Error: Could not find mkcert certificates${NC}"
    echo "Searched in: /mnt/c/Users/*/AppData/Local/mkcert/certs/"
    echo ""
    echo "You can specify the path manually by running:"
    echo "  MKCERT_PATH=/path/to/certs bash $0"
    echo ""
    echo "Example:"
    echo "  MKCERT_PATH=/mnt/c/Users/yourusername/AppData/Local/mkcert/certs bash $0"
    exit 1
fi

# Copy certificates that exist
COPIED_COUNT=0

# Copy all dev-*.crt files if they exist
if ls "$CERT_SOURCE"/dev-*.crt >/dev/null 2>&1; then
    cp "$CERT_SOURCE"/dev-*.crt ~/.local/share/certs/
    chmod 644 ~/.local/share/certs/*.crt  # Certs: owner write, all read
    COPIED_COUNT=$((COPIED_COUNT + $(ls "$CERT_SOURCE"/dev-*.crt 2>/dev/null | wc -l)))
    echo -e "${GREEN}✓ Copied certificate files${NC}"
fi

# Copy all dev-*.key files if they exist
if ls "$CERT_SOURCE"/dev-*.key >/dev/null 2>&1; then
    cp "$CERT_SOURCE"/dev-*.key ~/.local/share/certs/
    chmod 600 ~/.local/share/certs/*.key  # Keys: owner read/write only
    COPIED_COUNT=$((COPIED_COUNT + $(ls "$CERT_SOURCE"/dev-*.key 2>/dev/null | wc -l)))
    echo -e "${GREEN}✓ Copied key files${NC}"
fi

if [ $COPIED_COUNT -eq 0 ]; then
    echo -e "${RED}Error: No certificate files were copied${NC}"
    echo "Looked for dev-*.crt and dev-*.key files in: $CERT_SOURCE"
    exit 1
fi

# Create symbolic links for Docker secrets (only for files that exist)
echo -e "${GREEN}Creating Docker secret links...${NC}"

# Registry certificate
if [ -f ~/.local/share/certs/dev-registry.localhost.crt ]; then
    ln -sf ~/.local/share/certs/dev-registry.localhost.crt ~/.docker/secrets/registry_cert
    ln -sf ~/.local/share/certs/dev-registry.localhost.key ~/.docker/secrets/registry_key
    echo "  ✓ Registry certificates linked"
fi

# Wildcard localhost certificate
if [ -f ~/.local/share/certs/dev-localhost-wild.crt ]; then
    ln -sf ~/.local/share/certs/dev-localhost-wild.crt ~/.docker/secrets/localhost_cert
    ln -sf ~/.local/share/certs/dev-localhost-wild.key ~/.docker/secrets/localhost_key
    echo "  ✓ Localhost wildcard certificates linked"
fi

echo -e "${GREEN}✅ Certificates copied successfully!${NC}"
echo "📁 Location: ~/.local/share/certs/"
echo "🔐 Docker secrets: ~/.docker/secrets/"

# Verify
echo -e "\n${GREEN}Installed certificates:${NC}"
ls -la ~/.local/share/certs/dev-*.{crt,key} 2>/dev/null | awk '{print "  " $9, "(" $1 ")"}'
'@ | Out-File -FilePath $wslScriptPath -Encoding UTF8 -NoNewline

# 8. Create docker-compose.override.yml template
$dockerComposePath = "$certBase\docker-compose.override.template.yml"
@"
# Docker Compose Override for Local Development with TLS
# Copy this to your project as docker-compose.override.yml

version: '3.8'

services:
  # Example with Traefik reverse proxy
  traefik:
    image: traefik:v3.0
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.file.directory=/dynamic
      - --providers.file.watch=true
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.dashboard=true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - `${HOME}/.local/share/certs:/certs:ro
      - ./dynamic:/dynamic:ro
    restart: unless-stopped

  # Example: Local Docker Registry with TLS via Traefik
  registry:
    image: registry:2
    restart: unless-stopped
    environment:
      REGISTRY_HTTP_ADDR: :5000
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
    volumes:
      - registry-data:/var/lib/registry
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.registry.rule=Host(\`registry.localhost\`)"
      - "traefik.http.routers.registry.entrypoints=websecure"
      - "traefik.http.routers.registry.tls=true"
      - "traefik.http.services.registry.loadbalancer.server.port=5000"

  # Example: Airflow webserver with TLS via Traefik
  airflow-webserver:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.airflow.rule=Host(\`airflow-prod-high.localhost\`)"
      - "traefik.http.routers.airflow.entrypoints=websecure"
      - "traefik.http.routers.airflow.tls=true"
      - "traefik.http.services.airflow.loadbalancer.server.port=8080"

volumes:
  registry-data:

# Note: Create a dynamic/tls.yml file with:
# tls:
#   certificates:
#     - certFile: "/certs/dev-registry.localhost.crt"
#       keyFile: "/certs/dev-registry.localhost.key"
#     - certFile: "/certs/dev-localhost-wild.crt"
#       keyFile: "/certs/dev-localhost-wild.key"
"@ | Out-File -FilePath $dockerComposePath -Encoding UTF8

# 9. Create the Traefik TLS configuration template
$traefikTlsPath = "$certBase\tls.yml.template"
@"
# Traefik Dynamic TLS Configuration
# Place this in your project's dynamic/tls.yml file

tls:
  certificates:
    # SNI: registry.localhost
    - certFile: "/certs/dev-registry.localhost.crt"
      keyFile: "/certs/dev-registry.localhost.key"
    # SNI: *.localhost (covers all single-level subdomains)
    - certFile: "/certs/dev-localhost-wild.crt"
      keyFile: "/certs/dev-localhost-wild.key"
  
  # Optional: Set default certificate for unmatched SNI
  stores:
    default:
      defaultCertificate:
        certFile: "/certs/dev-localhost-wild.crt"
        keyFile: "/certs/dev-localhost-wild.key"
"@ | Out-File -FilePath $traefikTlsPath -Encoding UTF8

# 10. Display summary and next steps
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "    Certificate Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nGenerated Files:" -ForegroundColor Yellow
Write-Host "  Certificates: $certPath\$env_prefix-*.{crt,key}"
Write-Host "  Documentation: $fingerprintFile"
Write-Host "  WSL Script: $wslScriptPath"
Write-Host "  Docker Template: $dockerComposePath"
Write-Host "  Traefik TLS Template: $traefikTlsPath"

Write-Host "`nSupported Domains:" -ForegroundColor Green
Write-Host "  - localhost"
Write-Host "  - registry.localhost"
Write-Host "  - *.localhost (any single-level subdomain)"
Write-Host "    Examples:"
Write-Host "      • airflow-prod-high.localhost"
Write-Host "      • app-customer-staging.localhost"
Write-Host "      • api-internal-dev.localhost"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. In WSL, run the copy script:" -ForegroundColor White
Write-Host "     bash /mnt/c/Users/`$env:USERNAME/AppData/Local/mkcert/copy-to-wsl.sh" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Copy the Traefik TLS config to your project:" -ForegroundColor White
Write-Host "     mkdir -p /path/to/project/dynamic" -ForegroundColor Gray
Write-Host "     cp $traefikTlsPath /path/to/project/dynamic/tls.yml" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Use the docker-compose template for your services:" -ForegroundColor White
Write-Host "     cp $dockerComposePath /path/to/project/docker-compose.override.yml" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. Verify fingerprints match between Windows and WSL:" -ForegroundColor White
Write-Host "     sha256sum ~/.local/share/certs/dev-*.crt" -ForegroundColor Gray

Write-Host "`nSecurity Reminders:" -ForegroundColor Red
Write-Host "  - NEVER commit *.key files to git"
Write-Host "  - These certs are for LOCAL DEVELOPMENT ONLY"
Write-Host "  - Rotate certificates every 6-12 months"
Write-Host "  - Fingerprints documented in: $fingerprintFile"

# 11. Open documentation folder for review
Write-Host "`nOpening documentation folder..." -ForegroundColor Green
Start-Process explorer.exe $docPath