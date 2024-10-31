FROM odoo:17
LABEL Author="sucesstools.com"
USER root

RUN apt-get update && \
    apt-get install --no-install-recommends -y nano && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER odoo
