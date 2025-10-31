# Minimal Kerberos Sidecar Container (RECOMMENDED)
#
# Purpose: Manages Kerberos tickets ONLY - no connectivity tools
#
# ✓ This is the RECOMMENDED default for all deployments
#
# Size: ~50 MB (vs 312 MB legacy bloated version)
# Packages: 15-20 (vs 120+ legacy bloated version)
#
# Design Philosophy - Separation of Concerns:
# - Sidecar: Manages Kerberos tickets (this image)
# - Testing: Use separate test containers (platform/sqlcmd-test, platform/kerberos-test)
# - No bloat: No ODBC, no Python, no build tools
#
# What's NOT here (moved to separate test containers):
# - msodbcsql18, mssql-tools18 → platform/sqlcmd-test
# - unixodbc, freetds → Test containers
# - python3, py3-pip → platform/kerberos-test
# - gcc, g++, *-dev → REMOVED (build-time only)
#
# When to use:
# - ALL new deployments (local dev, Kubernetes, Astronomer)
# - Anywhere you need Kerberos ticket management
# - Production: Share /krb5/cache volume with application containers
#
# When NOT to use:
# - If you need the legacy bloated version: make build-legacy
#
# To build: make build (default)
#
# Corporate Artifactory & Alternative Base Images:
# - Set IMAGE_ALPINE build arg to use corporate registry mirrors
# - Compatible with Alpine Linux and Chainguard Wolfi base images
#
# Examples:
#   Alpine (default):
#     docker build -t platform/kerberos-sidecar:minimal .
#
#   Corporate Artifactory:
#     docker build --build-arg IMAGE_ALPINE=artifactory.company.com/alpine:3.19 \
#       -t platform/kerberos-sidecar:minimal .
#
#   Chainguard Wolfi (requires authentication to cgr.dev):
#     docker build --build-arg IMAGE_ALPINE=cgr.dev/chainguard/wolfi-base:latest \
#       -t platform/kerberos-sidecar:minimal .
#
# Note: Chainguard images provide SLSA Level 3 provenance and are maintained
# with security updates. They work seamlessly with this Dockerfile as they
# include the same apk package manager and required krb5 packages.

ARG IMAGE_ALPINE
FROM ${IMAGE_ALPINE:-alpine:3.19}

# Install ONLY Kerberos essentials
# No build tools, no ODBC, no SQL tools, no Python
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    bash \
    curl \
    ca-certificates

# Create directories for Kerberos configuration and cache
RUN mkdir -p /krb5/conf /krb5/cache /krb5/keytabs /scripts

# Copy the ticket management and health check scripts
COPY scripts/kerberos-ticket-manager.sh /scripts/
COPY scripts/health-check.sh /scripts/
RUN chmod +x /scripts/kerberos-ticket-manager.sh /scripts/health-check.sh

# Set environment variables for Kerberos
ENV KRB5_CONFIG=/krb5/conf/krb5.conf \
    KRB5CCNAME=/krb5/cache/krb5cc \
    KRB5_TRACE=/dev/stdout

# Health check - simple and effective
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD klist -s || exit 1

# Default command - run the ticket manager
CMD ["/scripts/kerberos-ticket-manager.sh"]
