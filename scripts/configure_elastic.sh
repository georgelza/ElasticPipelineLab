#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   configure_elastic.sh
#   Description           :   Configure Elasticsearch (ILM + index templates)
#                             and Kibana (data views) for the log pipeline
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Steps:
#     1. Ensure Elasticsearch is reachable (kubectl port-forward)
#     2. Create the `logs-ilm` ILM policy (hot -> delete)
#     3. Create the `logs-template` composable index template for
#        logs-* (picks up logs-prod-nonpci-syslog, logs-prod-nonpci-filebeat, ...)
#     4. Ensure Kibana is reachable (kubectl port-forward)
#     5. Create the Kibana data view:
#            logs-prod-nonpci-*  (time field @timestamp) - all feeds of the
#            simulated prod-nonpci account (syslog/filebeat/fluentbit/log4j)
#
#   Idempotent — safe to re-run.
#
#   Usage: ./configure_elastic.sh
#
#   Env: ES_NAMESPACE  Kubernetes namespace (default: elastic)
#        KIBANA_BASE   Kibana basePath (default: /kibana)
#
################################################################################################################################
set -euo pipefail

ES_NAMESPACE="${ES_NAMESPACE:-elastic}"
KIBANA_BASE="${KIBANA_BASE:-/kibana}"
ES_PORT=9200
KIBANA_PORT=5601

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

# ── 1. Elasticsearch reachable ───────────────────────────────────────────────
# Reuses any already-running forward (e.g. one left by configure_es_sink.sh).
info "1. Ensuring Elasticsearch is reachable at localhost:${ES_PORT} (kubectl port-forward)..."
if ! curl -fsS "http://localhost:${ES_PORT}/" >/dev/null 2>&1; then
    if [ -f /tmp/es-pf.pid ] && kill -0 "$(cat /tmp/es-pf.pid)" 2>/dev/null; then
        say "Reusing existing ES port-forward (pid $(cat /tmp/es-pf.pid))"
    else
        nohup kubectl port-forward service/elasticsearch "${ES_PORT}:9200" -n "${ES_NAMESPACE}" \
            >/tmp/es-pf.log 2>&1 &
        echo $! > /tmp/es-pf.pid
        if ! wait_for "ES" 60 curl -fsS "http://localhost:${ES_PORT}/" ; then
            die "Elasticsearch not reachable on localhost:${ES_PORT} after 60s — is the vcluster up (make deployk8s)?"
        fi
        say "Persistent ES port-forward started (pid $(cat /tmp/es-pf.pid))"
    fi
else
    say "ES already reachable on localhost:${ES_PORT} (reusing existing forward)"
fi

info "   Waiting for cluster health (green/yellow)..."
HEALTH=$(curl -fsS "http://localhost:${ES_PORT}/_cluster/health" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null || echo "red")
say "Cluster status: ${HEALTH}"

# ── 2. ILM policy ────────────────────────────────────────────────────────────
info "2. Creating ILM policy 'logs-ilm'..."
curl -fsS -X PUT "http://localhost:${ES_PORT}/_ilm/policy/logs-ilm" \
    -H 'Content-Type: application/json' \
    -d '{
          "policy": {
            "phases": {
              "hot": {
                "actions": {
                  "rollover": { "max_age": "30d", "max_size": "50gb" },
                  "set_priority": { "priority": 100 }
                }
              },
              "delete": {
                "min_age": "90d",
                "actions": { "delete": {} }
              }
            }
          }
        }' >/dev/null
say "ILM policy 'logs-ilm' created"

# ── 3. Composable index template ─────────────────────────────────────────────
info "3. Creating composable index template 'logs-template' for logs-*..."
curl -fsS -X PUT "http://localhost:${ES_PORT}/_index_template/logs-template" \
    -H 'Content-Type: application/json' \
    -d '{
          "index_patterns": ["logs-*", "filebeat-*"],
          "priority": 500,
          "template": {
            "settings": {
              "number_of_shards": 1,
              "number_of_replicas": 1,
              "index.lifecycle.name": "logs-ilm"
            },
            "mappings": {
              "properties": {
                "@timestamp": { "type": "date" },
                "ISODATE":     { "type": "date" },
                "MESSAGE":     { "type": "text" },
                "message":     { "type": "text" }
              }
            }
          }
        }' >/dev/null
say "Index template 'logs-template' created"

# ── 4. Kibana reachable ──────────────────────────────────────────────────────
info "4. Ensuring Kibana is reachable at localhost:${KIBANA_PORT}${KIBANA_BASE}..."
if ! curl -fsS "http://localhost:${KIBANA_PORT}${KIBANA_BASE}/api/status" >/dev/null 2>&1; then
    kubectl port-forward service/kibana "${KIBANA_PORT}:5601" -n "${ES_NAMESPACE}" &
    KIBANA_PF_PID=$!
    trap 'kill "${PF_PID:-}" "${KIBANA_PF_PID:-}" 2>/dev/null || true' EXIT
    if ! wait_for "Kibana" 120 curl -fsS "http://localhost:${KIBANA_PORT}${KIBANA_BASE}/api/status" ; then
        die "Kibana not reachable on localhost:${KIBANA_PORT}${KIBANA_BASE} after 120s"
    fi
    say "Kibana reachable via port-forward (pid ${KIBANA_PF_PID})"
else
    say "Kibana already reachable on localhost:${KIBANA_PORT}${KIBANA_BASE} (reusing existing forward)"
fi

# ── 5. Kibana data views (saved-objects API, allowNoIndex) ───────────────────
info "5. Creating Kibana data views..."
KIBANA_API="http://localhost:${KIBANA_PORT}${KIBANA_BASE}/api/saved_objects/index-pattern"

create_data_view() { # create_data_view <id> <title> <timefield>
    local id="$1" title="$2" timefield="$3"
    local body
    body=$(cat <<EOF
{
  "attributes": {
    "title": "${title}",
    "timeFieldName": "${timefield}",
    "allowNoIndex": "true"
  }
}
EOF
)
    local code
    code=$(curl -sS -o /tmp/kibana-dv.json -w '%{http_code}' \
        -X POST "${KIBANA_API}/${id}" \
        -H 'Content-Type: application/json' \
        -H 'kbn-xsrf: true' \
        -d "${body}" || true)
    case "${code}" in
        200) say "Data view '${title}' created (id ${id})" ;;
        409) say "Data view '${title}' already exists (id ${id}, HTTP 409)" ;;
        *)   say "Data view '${title}' HTTP ${code} — $(cat /tmp/kibana-dv.json 2>/dev/null | head -c 200)" ;;
    esac
}

create_data_view "logs-prod-nonpci" "logs-prod-nonpci-*" "@timestamp"

info "Done — Elasticsearch ILM/templates + Kibana data views configured."
