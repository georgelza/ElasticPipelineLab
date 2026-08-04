#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   configure_kibana_dashboards.sh
#   Description           :   Provision basic Kibana dashboards for the three
#                             log feeds (syslog / filebeat / fluentbit):
#                               - one per-feed data view (index-pattern)
#                               - one saved search (latest-events table)
#                               - two visualizations (volume-over-time
#                                 histogram + top-terms breakdown)
#                               - one dashboard per feed
#                             All objects are created via the Kibana Saved
#                             Objects API (_bulk_create) and are IDEMPOTENT
#                             (existing objects are left untouched; the script
#                             reports each as created / already-exists).
#
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Steps:
#     1. Ensure Elasticsearch is reachable (kubectl port-forward)
#     2. Ensure Kibana is reachable (kubectl port-forward)
#     3. Bulk-create the data views + saved searches + visualizations +
#        dashboards for the 3 feeds
#
#   Usage: ./configure_kibana_dashboards.sh
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

# ── 2. Kibana reachable ──────────────────────────────────────────────────────
info "2. Ensuring Kibana is reachable at localhost:${KIBANA_PORT}${KIBANA_BASE}..."
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

# ── 3. Build + bulk-create the saved objects ─────────────────────────────────
info "3. Building the saved-objects payload (python3)..."
PAYLOAD="/tmp/kibana-dashboards-payload.json"
python3 - "${PAYLOAD}" <<'PY'
import json
import sys

PAYLOAD = sys.argv[1]
KIBANA_VERSION = "8.13.4"


def ref(so_id, name, so_type):
    return {"id": so_id, "name": name, "type": so_type}


def search_source(index_id, query=""):
    return {
        "query": {"query": query, "language": "kuery"},
        "filter": [],
        "indexRefName": "kibanaSavedObjectMeta.searchSourceJSON.index",
    }


def index_pattern(so_id, title):
    return {
        "type": "index-pattern",
        "id": so_id,
        "attributes": {
            "title": title,
            "timeFieldName": "@timestamp",
            "allowNoIndex": "true",
        },
        "references": [],
    }


def saved_search(so_id, title, columns, index_id):
    return {
        "type": "search",
        "id": so_id,
        "attributes": {
            "title": title,
            "description": "",
            "hits": 0,
            "columns": columns,
            "sort": [["@timestamp", "desc"]],
            "version": 1,
            "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(search_source(index_id))},
        },
        "references": [ref(index_id, "kibanaSavedObjectMeta.searchSourceJSON.index", "index-pattern")],
    }


def visualization(so_id, title, index_id, vis):
    return {
        "type": "visualization",
        "id": so_id,
        "attributes": {
            "title": title,
            "description": "",
            "visState": json.dumps(vis),
            "uiStateJSON": "{}",
            "version": 1,
            "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(search_source(index_id))},
        },
        "references": [ref(index_id, "kibanaSavedObjectMeta.searchSourceJSON.index", "index-pattern")],
    }


def histogram(so_id, title, index_id):
    vis = {
        "title": title,
        "type": "histogram",
        "aggs": [
            {"id": "1", "enabled": True, "type": "count", "schema": "metric", "params": {}},
            {
                "id": "2", "enabled": True, "type": "date_histogram", "schema": "segment",
                "params": {
                    "field": "@timestamp", "interval": "auto", "min_doc_count": 1,
                    "drop_partials": False, "extended_bounds": {}, "timeRange": {},
                },
            },
        ],
        "params": {
            "type": "histogram",
            "grid": {"categoryLines": False},
            "categoryAxes": [
                {
                    "id": "CategoryAxis-1", "type": "category", "position": "bottom", "show": True,
                    "style": {}, "scale": {"type": "linear"},
                    "labels": {"show": True, "filter": True, "truncate": 100}, "title": {},
                }
            ],
            "valueAxes": [
                {
                    "id": "ValueAxis-1", "name": "LeftAxis-1", "type": "value", "position": "left",
                    "show": True, "style": {}, "scale": {"type": "linear", "mode": "normal"},
                    "labels": {"show": True, "rotate": 0, "filter": False, "truncate": 100},
                    "title": {"text": "Count"},
                }
            ],
            "seriesParams": [
                {
                    "show": "true", "type": "histogram", "mode": "stacked",
                    "data": {"label": "Count", "id": "1"}, "valueAxis": "ValueAxis-1",
                    "drawLinesBetweenPoints": True, "showCircles": True,
                }
            ],
            "addTooltip": True,
            "addLegend": True,
            "legendPosition": "right",
            "timeseries": [],
            "palette": {"type": "palette", "name": "kibana_palette"},
            "labels": {"show": False},
        },
    }
    return visualization(so_id, title, index_id, vis)


def terms_pie(so_id, title, index_id, field, size=10):
    vis = {
        "title": title,
        "type": "pie",
        "aggs": [
            {"id": "1", "enabled": True, "type": "count", "schema": "metric", "params": {}},
            {
                "id": "2", "enabled": True, "type": "terms", "schema": "segment",
                "params": {
                    "field": field, "size": size, "order": "desc", "orderBy": "1",
                    "otherBucket": True, "missingBucket": True,
                },
            },
        ],
        "params": {
            "type": "pie", "addTooltip": True, "addLegend": True, "legendPosition": "right",
            "isDonut": True, "labels": {"show": True, "truncate": 100},
            "palette": {"type": "palette", "name": "kibana_palette"},
        },
    }
    return visualization(so_id, title, index_id, vis)


def dashboard(so_id, title, description, index_id, panels):
    panels_json = json.dumps(panels)
    references = [
        ref(p["id"], "{}:panel_{}".format(p["panelIndex"], p["panelIndex"]), p["type"])
        for p in panels
    ]
    return {
        "type": "dashboard",
        "id": so_id,
        "attributes": {
            "title": title,
            "description": description,
            "hits": 0,
            "version": 1,
            "timeRestore": True,
            "timeFrom": "now-24h",
            "timeTo": "now",
            "panelsJSON": panels_json,
            "optionsJSON": json.dumps({"useMargins": True, "syncColors": True, "hidePanelTitles": False}),
            "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(search_source(index_id))},
        },
        "references": references,
    }


def panel(i, x, y, w, h, panel_type, panel_id, panel_title):
    return {
        "version": KIBANA_VERSION,
        "gridData": {"x": x, "y": y, "w": w, "h": h, "i": str(i)},
        "panelIndex": str(i),
        "type": panel_type,
        "id": panel_id,
        "embeddableConfig": {"title": panel_title},
    }


# ── feed definitions ─────────────────────────────────────────────────────────
feeds = [
    {
        "label": "syslog",
        "index_id": "logs-prod-nonpci-syslog",
        "index_title": "logs-prod-nonpci-syslog*",
        "dash_id": "dash-logs-prod-nonpci-syslog",
        "dash_title": "Syslog — Overview (prod-nonpci)",
        "dash_desc": "Basic overview for the syslog feed (logs-prod-nonpci-syslog).",
        "search_id": "search-syslog-latest",
        "search_title": "Syslog — latest events",
        "search_cols": ["@timestamp", "HOST", "PROGRAM", "MESSAGE"],
        "vis_volume": ("vis-syslog-volume", "Syslog volume over time"),
        "vis_terms": ("vis-syslog-top-programs", "Top programs (PROGRAM)", "PROGRAM.keyword"),
    },
    {
        "label": "filebeat",
        "index_id": "logs-prod-nonpci-filebeat",
        "index_title": "logs-prod-nonpci-filebeat*",
        "dash_id": "dash-logs-prod-nonpci-filebeat",
        "dash_title": "Filebeat — Overview (prod-nonpci)",
        "dash_desc": "Basic overview for the filebeat feed (logs-prod-nonpci-filebeat).",
        "search_id": "search-filebeat-latest",
        "search_title": "Filebeat — latest events",
        "search_cols": ["@timestamp", "host.hostname", "log.file.path", "message"],
        "vis_volume": ("vis-filebeat-volume", "Filebeat volume over time"),
        "vis_terms": ("vis-filebeat-top-hosts", "Top hosts (host.hostname)", "host.hostname.keyword"),
    },
    {
        "label": "fluentbit",
        "index_id": "logs-prod-nonpci-fluentbit",
        "index_title": "logs-prod-nonpci-fluentbit*",
        "dash_id": "dash-logs-prod-nonpci-fluentbit",
        "dash_title": "FluentBit — Overview (prod-nonpci)",
        "dash_desc": "Basic overview for the fluentbit feed (logs-prod-nonpci-fluentbit).",
        "search_id": "search-fluentbit-latest",
        "search_title": "FluentBit — latest events",
        "search_cols": ["@timestamp", "stream", "log"],
        "vis_volume": ("vis-fluentbit-volume", "FluentBit volume over time"),
        "vis_terms": ("vis-fluentbit-streams", "Stream split (stdout/stderr)", "stream.keyword"),
    },
]

objects = []
for f in feeds:
    objects.append(index_pattern(f["index_id"], f["index_title"]))
    objects.append(saved_search(f["search_id"], f["search_title"], f["search_cols"], f["index_id"]))

    vis_volume_id, vis_volume_title = f["vis_volume"]
    vis_terms_id, vis_terms_title, vis_terms_field = f["vis_terms"]
    objects.append(histogram(vis_volume_id, vis_volume_title, f["index_id"]))
    objects.append(terms_pie(vis_terms_id, vis_terms_title, f["index_id"], vis_terms_field))

    objects.append(
        dashboard(
            f["dash_id"], f["dash_title"], f["dash_desc"], f["index_id"],
            [
                panel(1, 0, 0, 48, 15, "visualization", vis_volume_id, vis_volume_title),
                panel(2, 0, 15, 48, 15, "visualization", vis_terms_id, vis_terms_title),
                panel(3, 0, 30, 48, 20, "search", f["search_id"], f["search_title"]),
            ],
        )
    )

with open(PAYLOAD, "w") as fh:
    json.dump(objects, fh)
print("built {} saved objects".format(len(objects)))
PY

info "4. Bulk-creating saved objects (POST ${KIBANA_BASE}/api/saved_objects/_bulk_create)..."
RESP="/tmp/kibana-dashboards-response.json"
HTTP_CODE=$(curl -sS -o "${RESP}" -w '%{http_code}' \
    -X POST "http://localhost:${KIBANA_PORT}${KIBANA_BASE}/api/saved_objects/_bulk_create" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    --data-binary @"${PAYLOAD}" || true)

if [ "${HTTP_CODE}" != "200" ]; then
    die "Saved Objects bulk-create HTTP ${HTTP_CODE} — $(head -c 400 "${RESP}" 2>/dev/null)"
fi

python3 - "${RESP}" <<'PY'
import json
import sys

with open(sys.argv[1]) as fh:
    resp = json.load(fh)

created = exists = failed = 0
for so in resp.get("saved_objects", []):
    err = so.get("error") or {}
    code = err.get("statusCode")
    label = "{}:{}".format(so.get("type"), so.get("id"))
    if code == 409:
        print("  ~ {} already exists".format(label))
        exists += 1
    elif err:
        print("  ✗ {} HTTP {}: {}".format(label, code, err.get("message", "")[:120]))
        failed += 1
    else:
        print("  ✓ {} created".format(label))
        created += 1

print("── created: {} · already-exists: {} · failed: {}".format(created, exists, failed))
if failed:
    sys.exit(1)
PY

info "Done — open the dashboards in Kibana (Dashboard → Syslog/Filebeat/FluentBit — Overview)."
