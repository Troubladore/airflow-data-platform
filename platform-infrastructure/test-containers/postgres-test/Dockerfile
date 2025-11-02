# =============================================================================
# PostgreSQL Test Container Dockerfile
# =============================================================================
#
# PURPOSE:
#   Provides a minimal Alpine-based container with PostgreSQL client tools
#   and Kerberos GSSAPI support for testing database connectivity with
#   Kerberos authentication.
#
# FEATURES:
#   - PostgreSQL 17 client (psql) with GSSAPI support
#   - Kerberos client libraries for authentication
#   - unixODBC for ODBC-based database connectivity
#   - Runs as non-root user (testuser, uid 10001)
#   - Customizable base image via BASE_IMAGE build argument
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
#
# USAGE:
#   Build with defaults:
#     docker build -t postgres-test .
#
#   Build with custom base image:
#     docker build --build-arg BASE_IMAGE=alpine:3.19 -t postgres-test .
#
# MIGRATION NOTE:
#   This replaces kerberos/kerberos-sidecar/Dockerfile.postgres-test
#   Changes from original:
#   - Switched from postgres:16-alpine to configurable Alpine base
#   - Added unixODBC packages for ODBC connectivity
#   - Added non-root user (testuser, uid 10001)
#   - Added BASE_IMAGE build argument for corporate flexibility
#
# =============================================================================

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install PostgreSQL client, Kerberos, and ODBC packages
RUN apk add --no-cache \
    postgresql17-client \
    krb5 \
    krb5-libs \
    krb5-conf \
    unixodbc \
    unixodbc-dev \
    ca-certificates \
    tzdata

# Create non-root user for security
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

# Switch to non-root user
USER testuser

# Default command (can be overridden at runtime)
CMD ["/bin/sh"]
