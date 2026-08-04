#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   take_snapshot.sh
#   Description           :   Take an ad-hoc Elasticsearch snapshot of the
#                             account's log indices (logs-prod-nonpci-* — the
#                             syslog / filebeat / fluentbit / log4j feeds) into
#                             the prod-nonpci S3 snapshot repository. The same
#                             indices are also covered by the logs-slm SLM
#                             policy (daily 01:00 UTC, retention 5–50/30d).
#
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Steps:
#     1. Ensure Elasticsearch is reachable (kubectl port-forward)
#     2. Ensure the target repository (prod-nonpci) exists
#     3. PUT _snapshot/prod-nonpci/logs-prod-nonpci-<ts> with indices
#        logs-prod-nonpci-* (synchronous — waits for completion)
#     4. Verify the snapshot state is SUCCESS and report shards
#
#   Usage: ./take_snapshot.sh
#
#   Env: ES_NAMESPACE   Kubernetes namespace (default: elastic)
#        SNAPSHOT_REPO  Target repository (default: prod-nonpci)
#        SNAPSHOT_INDICES  Indices to snapshot (default: logs-prod-nonpci-*)
#
################################################################################################################################
set -euo pipefail

ES_NAMESPACE="${ES_NAMESPACE:-elastic}"
SNAPSHOT_REPO="${SNAPSHOT_REPO:-prod-nonpci}"
SNAPSHOT_INDICES="${SNAPSHOT_INDICES:-logs-prod-nonpci-*}"
ES_PORT=9200

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

# ── 2. Repository exists ─────────────────────────────────────────────────────
info "2. Checking repository '${SNAPSHOT_REPO}' exists..."
if ! curl -fsS "http://localhost:${ES_PORT}/_snapshot/${SNAPSHOT_REPO}" >/dev/null 2>&1; then
    die "Repository '${SNAPSHOT_REPO}' not found — run 'make s3-snapshots' first (registers the 8 classification repositories)."
fi
say "Repository '${SNAPSHOT_REPO}' exists"

# ── 3. Which indices are matched ─────────────────────────────────────────────
MATCHED=$(curl -fsS "http://localhost:${ES_PORT}/_cat/indices/${SNAPSHOT_INDICES}?h=index&s=index" 2>/dev/null || true)
if [ -z "${MATCHED}" ]; then
    say "No indices match '${SNAPSHOT_INDICES}' yet — snapshot will still be taken (ignore_unavailable), it will simply contain 0 shards."
else
    info "   Matching indices:"
    printf '      %s\n' ${MATCHED} | sed 's/^/      /'
fi

# ── 4. Take the snapshot (synchronous) ───────────────────────────────────────
SNAP_NAME="logs-prod-nonpci-$(date +%Y%m%d-%H%M%S)"
info "3. Taking snapshot '${SNAP_NAME}' → repo '${SNAPSHOT_REPO}' (indices ${SNAPSHOT_INDICES})..."
HTTP_CODE=$(curl -sS -o /tmp/es-snapshot.json -w '%{http_code}' \
    -X PUT "http://localhost:${ES_PORT}/_snapshot/${SNAPSHOT_REPO}/${SNAP_NAME}?wait_for_completion=true" \
    -H 'Content-Type: application/json' \
    -d "{
          \"indices\": \"${SNAPSHOT_INDICES}\",
          \"ignore_unavailable\": true,
          \"include_global_state\": false
        }" || true)
if [ "${HTTP_CODE}" != "200" ]; then
    die "Snapshot request HTTP ${HTTP_CODE} — $(head -c 400 /tmp/es-snapshot.json 2>/dev/null)"
fi

# ── 5. Verify ────────────────────────────────────────────────────────────────
STATE=$(python3 -c 'import json; print(json.load(open("/tmp/es-snapshot.json")).get("snapshot",{}).get("state","?"))' 2>/dev/null || echo "?")
SHARDS_TOTAL=$(python3 -c 'import json; d=json.load(open("/tmp/es-snapshot.json")).get("snapshot",{}).get("shards",{}); print(d.get("total",0))' 2>/dev/null || echo "?")
SHARDS_OK=$(python3 -c 'import json; d=json.load(open("/tmp/es-snapshot.json")).get("snapshot",{}).get("shards",{}); print(d.get("successful",0))' 2>/dev/null || echo "?")
if [ "${STATE}" = "SUCCESS" ]; then
    say "Snapshot '${SNAP_NAME}' SUCCESS (${SHARDS_OK}/${SHARDS_TOTAL} shards) in repo '${SNAPSHOT_REPO}'"
else
    die "Snapshot state '${STATE}' — check 'curl -s localhost:9200/_snapshot/${SNAPSHOT_REPO}/${SNAP_NAME}'"
fi

info "Done — '${SNAP_NAME}' is now in the '${SNAPSHOT_REPO}' repository (S3 bucket '${SNAPSHOT_REPO}')."
