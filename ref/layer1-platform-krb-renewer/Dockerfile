FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    krb5-user ca-certificates \
 && rm -rf /var/lib/apt/lists/*
ENV DEBIAN_FRONTEND=noninteractive
ENV KRB5_KEYTAB=/secrets/airflow.keytab
ENV KRB5_PRINCIPAL=
ENV KRB5_CCNAME=/ccache/krb5cc
ENV RENEW_SECONDS=3600
WORKDIR /opt/renewer
COPY renew.sh /opt/renewer/renew.sh
RUN chmod +x /opt/renewer/renew.sh
ENTRYPOINT ["/opt/renewer/renew.sh"]
