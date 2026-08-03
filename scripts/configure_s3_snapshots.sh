#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   configure_s3_snapshots.sh
#   Description           :   Register Elasticsearch S3 snapshot repositories on
#                             the RustFS object store — one repository per
#                             security-classification AWS account — plus an SLM
#                             policy for the logs-* indices.
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Naming model:
#     The S3 bucket name maps 1:1 to the source AWS account name (a "set of
#     information/systems that are aligned and managed together" from a
#     financial/governance perspective). The Elasticsearch snapshot repository
#     shares the same name, so:  account (bucket) name == repository name.
#
#     Log streams follow the `logs-<account>-<source>` topic convention
#     (e.g. logs-prod-nonpci-syslog / logs-prod-nonpci-filebeat /
#     logs-prod-nonpci-fluentbit for our simulated prod-nonpci account). A
#     wildcard on the account segment (logs-prod-nonpci-.* at the sink,
#     logs-prod-nonpci-* at the SLM policy) catches all of an account's feeds
#     and routes them into that account's repo/bucket.
#
#   Eight security-classification accounts (template — production maps ~18
#   accounts onto these; bucket == repo == account):
#       prod-pci, prod-nonpci, prod-unregulated, prod-ife,
#       nonprod-pci, nonprod-nonpci, nonprod-unregulated, nonprod-ife
#
#   S3 path convention (inside each bucket; <project name> is the FIRST
#   element, the <aws account name> — which IS the bucket — is the SECOND):
#       <endpoint>/<project name = log_analytics>/<aws account name>/
#       year=yyyy/month=mm/day=dd/<instanceId or Hostname>
#
#   Steps:
#     1. Ensure Elasticsearch is reachable (kubectl port-forward)
#     2. Create the eight security-classification buckets on RustFS (aws CLI)
#     3. Register one ES snapshot repository per bucket (verify=true)
#     4. Create the `logs-slm` SLM policy (logs-prod-nonpci-* → prod-nonpci)
#
#   Idempotent — safe to re-run (bucket/repo creation is skipped if present).
#
#   Usage: ./configure_s3_snapshots.sh
#
#   Env:  ES_NAMESPACE      Kubernetes namespace (default: elastic)
#         RUSTFS_ENDPOINT   Local RustFS S3 API endpoint (default: http://127.0.0.1:9000)
#         S3_INSTANCE_NAME  InstanceId/hostname segment of the base_path (default: es-node-1)
#         SLM_REPOSITORY    Repository targeted by the logs-slm policy (default: prod-nonpci)
#         SLM_INDICES       Indices matched by the logs-slm policy (default: logs-prod-nonpci-*)
#
################################################################################################################################
set -euo pipefail

# ── load .env (S3_PROJECT_NAME, S3_REGION, S3_ACCESS_KEY_ID, ...) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
    # shellcheck disable=SC1091
    set -a; source "${REPO_ROOT}/.env"; set +a
fi

ES_NAMESPACE="${ES_NAMESPACE:-elastic}"
RUSTFS_ENDPOINT="${RUSTFS_ENDPOINT:-http://127.0.0.1:9000}"
S3_INSTANCE_NAME="${S3_INSTANCE_NAME:-es-node-1}"
SLM_REPOSITORY="${SLM_REPOSITORY:-prod-nonpci}"
SLM_INDICES="${SLM_INDICES:-logs-prod-nonpci-*}"
ES_PORT=9200

# Eight security-classification accounts. The S3 bucket name maps 1:1 to the
# source AWS account (a set of systems aligned/managed together financially /
# governance wise), and the ES snapshot repository shares the same name.
# S3 bucket names must be lowercase. This is the template set — production
# accounts (~18) map onto these eight classifications.
ACCOUNTS=(
    "prod-pci"
    "prod-nonpci"
    "prod-unregulated"
    "prod-ife"
    "nonprod-pci"
    "nonprod-nonpci"
    "nonprod-unregulated"
    "nonprod-ife"
)

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

require() { # require <cmd> <hint>
    command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found — ${2:-}"
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

# ── 2. Create the eight classification buckets on RustFS ─────────────────────
require aws "install the AWS CLI (brew install awscli)"

if [ -z "${S3_ACCESS_KEY_ID:-}" ] || [ -z "${S3_SECRET_ACCESS_KEY:-}" ]; then
    die "S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY not set (check .env)"
fi
if [ -z "${S3_PROJECT_NAME:-}" ]; then
    die "S3_PROJECT_NAME not set (check .env)"
fi

# Base path inside each bucket: <project name> is the FIRST element (for our
# usage: log_analytics), the <aws account name> is the SECOND element (each
# account is a member of the project; the bucket itself == the account name),
# followed by the zero-padded date segments yyyy/mm/dd and the instance.
DATE_SEGMENTS="year=$(date +%Y)/month=$(date +%m)/day=$(date +%d)"
BASE_PATH_PREFIX="${S3_PROJECT_NAME}"

export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${S3_REGION:-af-south-1}"

info "2. Ensuring the eight security-classification buckets exist on ${RUSTFS_ENDPOINT}..."
for account in "${ACCOUNTS[@]}"; do
    if aws --endpoint-url "${RUSTFS_ENDPOINT}" s3api head-bucket --bucket "${account}" >/dev/null 2>&1; then
        say "Bucket '${account}' already exists"
    else
        aws --endpoint-url "${RUSTFS_ENDPOINT}" s3api create-bucket --bucket "${account}" \
            --region "${AWS_DEFAULT_REGION}" >/dev/null
        say "Bucket '${account}' created"
    fi
done

# ── 3. Register one ES snapshot repository per classification account ────────
# Bucket name == account name == repository name (aligned). The base_path is
# <project>/<account>/year=yyyy/month=mm/day=dd/<instance> — account is the
# SECOND path element (a member of the project).
info "3. Registering ES snapshot repositories (base_path: ${BASE_PATH_PREFIX}/<account>/${DATE_SEGMENTS}/${S3_INSTANCE_NAME})..."
for account in "${ACCOUNTS[@]}"; do
    base_path="${BASE_PATH_PREFIX}/${account}/${DATE_SEGMENTS}/${S3_INSTANCE_NAME}"
    code=$(curl -sS -o /tmp/es-repo.json -w '%{http_code}' \
        -X PUT "http://localhost:${ES_PORT}/_snapshot/${account}?verify=true" \
        -H 'Content-Type: application/json' \
        -d "{
              \"type\": \"s3\",
              \"settings\": {
                \"bucket\": \"${account}\",
                \"base_path\": \"${base_path}\",
                \"compress\": true
              }
            }" || true)
    case "${code}" in
        200) say "Repository '${account}' → bucket '${account}' (${base_path})" ;;
        *)
            say "Repository '${account}' HTTP ${code} — $(cat /tmp/es-repo.json 2>/dev/null | head -c 300)"
            ;;
    esac
done

# ── 4. SLM policy for the account's log feeds ────────────────────────────────
info "4. Creating SLM policy 'logs-slm' (${SLM_INDICES} → ${SLM_REPOSITORY}, daily 01:00 UTC)..."
code=$(curl -sS -o /tmp/es-slm.json -w '%{http_code}' \
    -X PUT "http://localhost:${ES_PORT}/_slm/policy/logs-slm" \
    -H 'Content-Type: application/json' \
    -d "{
          \"name\": \"logs-slm\",
          \"schedule\": \"0 0 1 * * ?\",
          \"repository\": \"${SLM_REPOSITORY}\",
          \"config\": {
            \"indices\": [\"${SLM_INDICES}\"],
            \"ignore_unavailable\": true,
            \"include_global_state\": false
          },
          \"retention\": {
            \"expire_after\": \"30d\",
            \"min_count\": 5,
            \"max_count\": 50
          }
        }" || true)
case "${code}" in
    200) say "SLM policy 'logs-slm' created" ;;
    *)   say "SLM policy 'logs-slm' HTTP ${code} — $(cat /tmp/es-slm.json 2>/dev/null | head -c 300)" ;;
esac

info "Done — S3 snapshot repositories (8) + SLM policy configured."
