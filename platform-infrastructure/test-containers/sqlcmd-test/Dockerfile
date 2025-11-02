# =============================================================================
# SQL Server Test Container Dockerfile (Microsoft ODBC Driver)
# =============================================================================
#
# PURPOSE:
#   Provides a minimal Alpine-based container with Microsoft SQL Server ODBC
#   driver and tools for testing SQL Server connectivity with Kerberos
#   authentication.
#
# FEATURES:
#   - Microsoft ODBC Driver 18 for SQL Server (msodbcsql18)
#   - Microsoft SQL Server command-line tools (mssql-tools18)
#   - Kerberos client libraries for authentication
#   - unixODBC for ODBC-based database connectivity
#   - Runs as non-root user (testuser, uid 10001)
#   - Customizable base image via BASE_IMAGE build argument
#   - Corporate Artifactory support via ODBC_DRIVER_URL build argument
#
# BUILD ARGUMENTS:
#   BASE_IMAGE: Base image to use (default: alpine:latest)
#               Can be overridden for corporate environments:
#               --build-arg BASE_IMAGE=registry.corp.com/alpine:3.19-hardened
#
#   ODBC_DRIVER_URL: URL base for downloading Microsoft ODBC driver packages
#                    Default: Microsoft download server
#                    Corporate: Set to Artifactory mirror URL
#
# SECURITY:
#   - Non-root user execution (principle of least privilege)
#   - Minimal package installation (reduced attack surface)
#   - No hardcoded credentials or secrets
#
# USAGE:
#   Build with defaults (downloads from Microsoft):
#     docker build -t platform/sqlcmd-test .
#
#   Build with custom base image:
#     docker build --build-arg BASE_IMAGE=alpine:3.19 -t platform/sqlcmd-test .
#
#   Build with corporate Artifactory mirror:
#     docker build \
#       --build-arg BASE_IMAGE=artifactory.corp.com/alpine:3.19 \
#       --build-arg ODBC_DRIVER_URL=https://artifactory.corp.com/mssql-drivers \
#       -t platform/sqlcmd-test .
#
# MIGRATION NOTE:
#   This replaces kerberos/kerberos-sidecar/Dockerfile.sqlcmd-test
#   Changes from original:
#   - Added non-root user (testuser, uid 10001)
#   - Standardized BASE_IMAGE build argument (was IMAGE_ALPINE)
#   - Added ODBC_DRIVER_URL build argument for corporate flexibility
#   - Simplified and documented the build process
#
# MICROSOFT DRIVERS:
#   - msodbcsql18: Microsoft ODBC Driver 18 for SQL Server
#   - mssql-tools18: sqlcmd and bcp command-line tools
#   - Both are distributed as Alpine APK files by Microsoft
#   - Kerberos authentication is fully supported
#
# =============================================================================

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install base packages: Kerberos, curl, unixODBC
# Note: These must be installed BEFORE Microsoft ODBC drivers
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    curl \
    gnupg \
    unixodbc \
    unixodbc-dev

# Install Microsoft ODBC Driver 18 for SQL Server
# Corporate environments: Override ODBC_DRIVER_URL to use Artifactory mirror
ARG ODBC_DRIVER_URL=https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5
RUN curl -O ${ODBC_DRIVER_URL}/msodbcsql18_18.3.2.1-1_amd64.apk && \
    curl -O ${ODBC_DRIVER_URL}/mssql-tools18_18.3.1.1-1_amd64.apk && \
    apk add --allow-untrusted msodbcsql18_18.3.2.1-1_amd64.apk && \
    apk add --allow-untrusted mssql-tools18_18.3.1.1-1_amd64.apk && \
    rm *.apk

# Create non-root user for security
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

# Switch to non-root user
USER testuser

# Default command (can be overridden at runtime)
CMD ["/bin/sh"]
