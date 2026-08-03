#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   configure_es_sink.sh
#   Description           :   Register / update the Kafka Connect Elasticsearch
#                             Sink connector (deployment part of the pipeline)
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Registers (or updates) the `elasticsearch-sink` connector on the Docker
#   Compose Kafka Connect cluster (REST API published on localhost:8083).
#
#   Topics consumed : logs-prod-nonpci-syslog     -> index logs-prod-nonpci-syslog
#                     logs-prod-nonpci-filebeat   -> index logs-prod-nonpci-filebeat
#                     logs-prod-nonpci-fluentbit  -> index logs-prod-nonpci-fluentbit
#                     logs-prod-nonpci-log4j      -> index logs-prod-nonpci-log4j
#                     (any logs-prod-nonpci-* topic -> same-named index, via wildcard)
#
#   Topics follow the `logs-<account>-<source>` convention (account segment =
#   FULL AWS account name, e.g. "prod-nonpci" for our simulated lab account),
#   so the connector subscribes with a single
#   `topics.regex: logs-prod-nonpci-.*` and writes to an index with the
#   same name as the topic (no per-topic mapping needed — the ES index template
#   in configure_elastic.sh matches logs-*). The indices are snapshotted into
#   the account's ES repository / S3 bucket (see configure_s3_snapshots.sh).
#
#   Because Elasticsearch runs inside the vcluster (k8s) while Kafka Connect
#   runs in Docker Compose, this script starts a `kubectl port-forward` for
#   the ES service and points the connector at `host.docker.internal:9200`
#   (Docker Desktop host alias for the port-forward listener).
#
#   Usage: ./configure_es_sink.sh
#
#   Env: CONNECT_URL   Kafka Connect REST endpoint  (default: http://localhost:8083)
#        ES_PF_PORT    Local port for the ES port-forward (default: 9200)
#        ES_NAMESPACE  Kubernetes namespace of the ES service (default: elastic)
#        CONNECTOR     Connector name (default: elasticsearch-sink)
#
################################################################################################################################
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ES_PF_PORT="${ES_PF_PORT:-9200}"
ES_NAMESPACE="${ES_NAMESPACE:-elastic}"
CONNECTOR="${CONNECTOR:-elasticsearch-sink}"

# ── helpers ──────────────────────────────────────────────────────────────────
say()  { printf '  ✓ %s\n' "$*"; }
info() { printf '── %s\n' "$*"; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

wait_for() { # wait_for <label> <timeout_sec> <cmd...>
    local label="$1" timeout="$2"; shift 2
    local n=0
    until "$@" >/dev/null 2>&1; do
        n=$((n + 1))
        if (( n > timeout )); then return 1; fi
        sleep 1
    done
    return 0
}

# ── 1. ES reachable via persistent port-forward (k8s -> localhost) ────────────
# NOTE: the ES sink connector needs host.docker.internal:${ES_PF_PORT} reachable
# CONTINUOUSLY, so the port-forward started here is deliberately left running
# (nohup + pidfile) after this script exits. Stop it with:
#   pkill -f "port-forward service/elasticsearch"   (or: kill "$(cat /tmp/es-pf.pid)")
info "1. Ensuring Elasticsearch is reachable at localhost:${ES_PF_PORT} (kubectl port-forward)..."
if ! curl -fsS "http://localhost:${ES_PF_PORT}/" >/dev/null 2>&1; then
    if [ -f /tmp/es-pf.pid ] && kill -0 "$(cat /tmp/es-pf.pid)" 2>/dev/null; then
        say "Reusing existing ES port-forward (pid $(cat /tmp/es-pf.pid))"
    else
        nohup kubectl port-forward service/elasticsearch "${ES_PF_PORT}:9200" -n "${ES_NAMESPACE}" \
            >/tmp/es-pf.log 2>&1 &
        echo $! > /tmp/es-pf.pid
        if ! wait_for "ES" 60 curl -fsS "http://localhost:${ES_PF_PORT}/" ; then
            die "Elasticsearch not reachable on localhost:${ES_PF_PORT} after 60s — is the vcluster up (make deployk8s)?"
        fi
        say "Persistent ES port-forward started (pid $(cat /tmp/es-pf.pid))"
    fi
else
    say "ES already reachable on localhost:${ES_PF_PORT} (reusing existing forward)"
fi

# ── 2. Kafka Connect REST must be up ─────────────────────────────────────────
info "2. Checking Kafka Connect REST at ${CONNECT_URL}..."
if ! curl -fsS "${CONNECT_URL}/connectors" >/dev/null 2>&1; then
    die "Kafka Connect not reachable at ${CONNECT_URL} — is the Compose stack up (make run)?"
fi
say "Kafka Connect reachable"

# ── 3. Register the ES sink connector (create-or-update) ─────────────────────
info "3. Registering connector '${CONNECTOR}'..."
# PUT /connectors/{name}/config expects the RAW config map as the body
# (no "name"/"config" wrapper — that form belongs to POST /connectors).
CONNECTOR_JSON=$(cat <<EOF
{
  "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
  "tasks.max": "1",
  "topics.regex": "logs-prod-nonpci-.*",
  "connection.url": "http://host.docker.internal:${ES_PF_PORT}",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "key.ignore": "true",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "schema.ignore": "true",
  "index.write.method": "insert",
  "behavior.on.malformed.documents": "warn",
  "behavior.on.null.values": "ignore",
  "flush.timeout.ms": "10000",
  "retry.backoff.ms": "1000"
}
EOF
)

HTTP_CODE=$(curl -sS -o /tmp/es-sink-connector.json -w '%{http_code}' \
    -X PUT "${CONNECT_URL}/connectors/${CONNECTOR}/config" \
    -H 'Content-Type: application/json' \
    -d "${CONNECTOR_JSON}")

case "${HTTP_CODE}" in
    200|201) say "Connector '${CONNECTOR}' registered (HTTP ${HTTP_CODE})" ;;
    409)     say "Connector '${CONNECTOR}' already exists (HTTP 409) — verifying config" ;;
    *)       die "Failed to register connector (HTTP ${HTTP_CODE}): $(cat /tmp/es-sink-connector.json 2>/dev/null)" ;;
esac

# ── 4. Wait for the connector to reach RUNNING ───────────────────────────────
info "4. Waiting for connector '${CONNECTOR}' to reach RUNNING state..."
CONNECTOR_STATUS="${CONNECT_URL}/connectors/${CONNECTOR}/status"
if wait_for "connector" 60 curl -fsS "${CONNECTOR_STATUS}" ; then
    STATE=$(curl -fsS "${CONNECTOR_STATUS}" | python3 -c \
        'import json,sys; s=json.load(sys.stdin); print(s.get("connector",{}).get("state","UNKNOWN"))' 2>/dev/null || echo "UNKNOWN")
    say "Connector state: ${STATE} (see ${CONNECTOR_STATUS} for details)"
else
    die "Connector did not become reachable within 60s — inspect ${CONNECTOR_STATUS}"
fi

info "Done — Kafka Connect is now streaming all logs-prod-nonpci-* topics into ES (same-named indices)."
