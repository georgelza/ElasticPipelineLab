FROM confluentinc/cp-server-connect-base:7.9.6

ENV CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components"

RUN echo "--> Installing Connector Plugins"

# Elasticsearch Sink Connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-elasticsearch:latest

USER appuser
