# Airflow 3.0.6 via Astronomer Runtime 3.0-10
FROM astrocrpublic.azurecr.io/runtime:3.0-10

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    unixodbc curl krb5-user gcc g++ \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

USER astro
COPY requirements.txt /tmp/req.txt
RUN pip install --no-cache-dir -r /tmp/req.txt
COPY airflow_plugins/ /usr/local/airflow/plugins/
