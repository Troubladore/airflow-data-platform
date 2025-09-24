# Kerberos Sidecar Container for Astronomer Airflow
# Purpose: Manages Kerberos tickets for SQL Server NT Authentication
FROM alpine:3.19

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
RUN curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/msodbcsql18_18.3.2.1-1_amd64.apk && \
    curl -O https://download.microsoft.com/download/3/5/5/355d7943-a338-41a7-858d-53b259ea33f5/mssql-tools18_18.3.1.1-1_amd64.apk && \
    apk add --allow-untrusted msodbcsql18_18.3.2.1-1_amd64.apk && \
    apk add --allow-untrusted mssql-tools18_18.3.1.1-1_amd64.apk && \
    rm *.apk

# Create directories for Kerberos configuration and cache
RUN mkdir -p /krb5/conf /krb5/cache /krb5/keytabs /scripts

# Copy the ticket management script
COPY scripts/kerberos-ticket-manager.sh /scripts/
RUN chmod +x /scripts/kerberos-ticket-manager.sh

# Set environment variables for Kerberos
ENV KRB5_CONFIG=/krb5/conf/krb5.conf \
    KRB5CCNAME=/krb5/cache/krb5cc \
    KRB5_TRACE=/dev/stdout

# Health check to ensure tickets are valid
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD klist -s || exit 1

# Default command - run the ticket manager
CMD ["/scripts/kerberos-ticket-manager.sh"]
