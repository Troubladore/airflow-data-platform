# =============================================================================
# Pagila Test Container Dockerfile
# =============================================================================
#
# PURPOSE:
#   Provides a minimal Alpine-based container with PostgreSQL client tools
#   for testing Pagila database connectivity and verifying data loads.
#
# FEATURES:
#   - PostgreSQL 17 client (psql) for database connections
#   - Minimal Alpine base for small image size
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
#     docker build -t pagila-test .
#
#   Build with custom base image:
#     docker build --build-arg BASE_IMAGE=alpine:3.19 -t pagila-test .
#
#   Test Pagila connection:
#     docker run --rm --network platform_network pagila-test \
#       psql -h pagila-postgres -U postgres -d pagila -c '\dt'
#
# =============================================================================

ARG BASE_IMAGE=alpine:latest
FROM ${BASE_IMAGE}

# Install PostgreSQL client and basic utilities
RUN apk add --no-cache \
    postgresql17-client \
    ca-certificates \
    tzdata

# Create non-root user for security
RUN addgroup -g 10001 testuser && \
    adduser -D -u 10001 -G testuser testuser

# Switch to non-root user
USER testuser

# Set working directory
WORKDIR /home/testuser

# Default command (can be overridden at runtime)
CMD ["/bin/sh"]