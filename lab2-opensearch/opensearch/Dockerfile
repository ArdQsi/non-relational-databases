ARG OS_VERSION=3.8.0
FROM opensearchproject/opensearch:${OS_VERSION}
ARG PROM_PLUGIN_VERSION=3.8.0.0

RUN /usr/share/opensearch/bin/opensearch-plugin install --batch \
    https://github.com/opensearch-project/opensearch-prometheus-exporter/releases/download/${PROM_PLUGIN_VERSION}/prometheus-exporter-${PROM_PLUGIN_VERSION}.zip
