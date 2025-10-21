# Kerberos Sidecar Container for Astronomer Airflow
# Purpose: Manages Kerberos tickets for SQL Server NT Authentication
#
# Corporate Artifactory Support:
# - Set IMAGE_ALPINE build arg for corporate registry
# - APK packages use Alpine repos (configure /etc/apk/repositories if needed)
# - ODBC drivers downloaded from Microsoft (can be cached in Artifactory)

ARG IMAGE_ALPINE
FROM ${IMAGE_ALPINE:-alpine:3.19}

# Install Kerberos client libraries and SQL Server ODBC drivers
RUN apk add --no-cache \
    krb5 \
    krb5-libs \
    krb5-conf \
    krb5-dev \
    bash \
    curl \
    gnupg \
    unixodbc \
    unixodbc-dev \
    freetds \
    freetds-dev \
    python3 \
    py3-pip \
    gcc \
    g++ \
    musl-dev \
    libffi-dev \
    openssl-dev

# Install Microsoft ODBC Driver for SQL Server (Alpine compatible)
# Corporate: If Artifactory mirrors these, set ODBC_DRIVER_URL build arg
ARG ODBC_DRIVER_URL=https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5
RUN curl -O ${ODBC_DRIVER_URL}/msodbcsql18_18.3.2.1-1_amd64.apk && \
    curl -O ${ODBC_DRIVER_URL}/mssql-tools18_18.3.1.1-1_amd64.apk && \
    apk add --allow-untrusted msodbcsql18_18.3.2.1-1_amd64.apk && \
    apk add --allow-untrusted mssql-tools18_18.3.1.1-1_amd64.apk && \
    rm *.apk

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

# Health check with structured output for diagnostics
# Use the health-check.sh script which provides detailed status
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /scripts/health-check.sh || exit 1

# Default command - run the ticket manager
CMD ["/scripts/kerberos-ticket-manager.sh"]
