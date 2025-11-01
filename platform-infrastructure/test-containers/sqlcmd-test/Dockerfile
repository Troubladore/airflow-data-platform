# =============================================================================
# SQL Server Test Container Dockerfile (FreeTDS-based)
# =============================================================================
#
# PURPOSE:
#   Provides a minimal Alpine-based container with FreeTDS SQL Server client
#   tools and Kerberos support for testing SQL Server connectivity with
#   Kerberos authentication.
#
# FEATURES:
#   - FreeTDS SQL Server client tools (open source alternative to mssql-tools)
#   - Kerberos client libraries for authentication
#   - unixODBC for ODBC-based database connectivity
#   - Runs as non-root user (testuser, uid 10001)
#   - Customizable base image via BASE_IMAGE build argument
#   - No Microsoft proprietary tools or EULA requirements
#
# BUILD ARGUMENTS:
#   BASE_IMAGE: Base image to use (default: alpine:latest)
#               Can be overridden for corporate environments:
#               --build-arg BASE_IMAGE=registry.corp.com/alpine:3.19-hardened
#
# SECURITY:
#   - Non-root user execution (principle of least privilege)
#   - Minimal package installation (reduced attack surface)
#   - No hardcoded credentials or secrets
#   - No external downloads (all packages from Alpine repos)
#
# USAGE:
#   Build with defaults:
#     docker build -t sqlcmd-test .
#
#   Build with custom base image:
#     docker build --build-arg BASE_IMAGE=alpine:3.19 -t sqlcmd-test .
#
# MIGRATION NOTE:
#   This replaces kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test
#   Changes from original:
#   - Switched from Microsoft mssql-tools18 to FreeTDS (open source)
#   - Removed MSSQL_TOOLS_URL download logic and complexity
#   - Removed architecture detection logic
#   - Removed .netrc authentication requirement
#   - Added non-root user (testuser, uid 10001)
#   - Standardized BASE_IMAGE build argument (was IMAGE_ALPINE)
#   - All dependencies from Alpine repos (no external downloads)
#
# FREETDS vs MSSQL-TOOLS:
#   FreeTDS provides functionally equivalent SQL Server connectivity:
#   - Full T-SQL support via tsql and ODBC
#   - Kerberos authentication support
#   - Microsoft-compatible TDS protocol
#   - No EULA restrictions
#   - Better for air-gapped environments (no external downloads)
#
# =============================================================================

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install FreeTDS, Kerberos, and ODBC packages
# Note: FreeTDS provides SQL Server connectivity without Microsoft proprietary tools
RUN apk add --no-cache \
    krb5 \
    curl \
    unixodbc \
    unixodbc-dev \
    freetds \
    freetds-dev

# Create non-root user for security
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

# Switch to non-root user
USER testuser

# Default command (can be overridden at runtime)
CMD ["/bin/sh"]
