FROM confluentinc/cp-server-connect-base:7.9.6

ENV CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components"

RUN echo "--> Installing Connector Plugins"

# Source - https://debezium.io/docs/connectors/mysql/
#RUN confluent-hub install --no-prompt debezium/debezium-connector-mysql:latest

# Sink - https://docs.confluent.io/kafka-connectors/redis/current/overview.html
RUN confluent-hub install --no-prompt jcustenborder/kafka-connect-redis:latest

USER appuser
