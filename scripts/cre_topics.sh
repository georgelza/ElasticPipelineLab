#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   cre_topics.sh
#   Description           :   Create Kafka topics for the Elastic log pipeline
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Creates the Kafka topics used by the log analytics pipeline.
#   Topics follow the `logs-<account>-<source>` convention — the account
#   segment is the FULL AWS account name (e.g. "prod-nonpci" for our lab) so
#   the ES sink connector subscribes to a whole account's feeds with a single
#   wildcard (`logs-prod-nonpci-.*`), which in turn maps to that account's ES
#   snapshot repository / S3 bucket:
#       logs-prod-nonpci-syslog     — syslog-ng forwarded logs (Docker Compose)
#       logs-prod-nonpci-filebeat   — Filebeat (Docker Compose) host logs
#       logs-prod-nonpci-fluentbit  — FluentBit (Kubernetes) container/pod logs
#       logs-prod-nonpci-log4j      — Log4j appender logs (applications)
#       logs-<account>-*            — future accounts/sources follow the same rule
#   (We currently simulate a single account: prod-nonpci.)
#
#   Usage: ./cre_topics.sh
#
#   Env: COMPOSE_PROJECT_NAME  Docker Compose project name  (default: elastic)
#        COMPOSE_FILE          Path to docker-compose.yml   (default: repo root)
#
################################################################################################################################
set -euo pipefail

VERSION="1.0.0"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-elastic}"

# Resolve docker compose file location — default to this repository's root
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT}/docker-compose.yml}"

# Format: "topic_name:partitions:replication_factor"
TOPICS=(
    "logs-prod-nonpci-syslog:2:1"
    "logs-prod-nonpci-filebeat:2:1"
    "logs-prod-nonpci-fluentbit:2:1"
    "logs-prod-nonpci-log4j:2:1"
)

# Log-source topics are flow events, not keyed state — they are created
# with the default cleanup policy (delete) and a bounded retention window so
# downstream/ES sink consumers can replay from earliest after an outage.
# Tune via BUS_RETENTION_MS if a longer window is required.
BUS_RETENTION_MS="${BUS_RETENTION_MS:-604800000}"   # 7 days

echo "═══════════════════════════════════════════════════════════"
echo "  Creating Kafka topics (project: ${COMPOSE_PROJECT_NAME})"
echo "═══════════════════════════════════════════════════════════"

for ENTRY in "${TOPICS[@]}"; do
    IFS=':' read -r TOPIC PARTITIONS REPLICATION <<< "$ENTRY"

    EXTRA_CONFIG=(--config "retention.ms=${BUS_RETENTION_MS}")
    case "$TOPIC" in
        logs-*)
            # Log source streams: explicit delete policy + retention window.
            EXTRA_CONFIG+=(--config "cleanup.policy=delete")
            ;;
    esac

    docker compose -f "$COMPOSE_FILE" exec -T broker kafka-topics \
        --create --topic "$TOPIC" \
        --bootstrap-server localhost:9092 \
        --partitions "$PARTITIONS" \
        --replication-factor "$REPLICATION" \
        "${EXTRA_CONFIG[@]}" 2>&1 || true

    # Check if topic already exists
    if docker compose -f "$COMPOSE_FILE" exec -T broker kafka-topics \
        --bootstrap-server localhost:9092 --list 2>/dev/null | grep -qx "$TOPIC"; then
        printf "  ✓ %-32s  exists  (partitions=%s, replication=%s)\n" "$TOPIC" "$PARTITIONS" "$REPLICATION"
    else
        printf "  ✓ %-32s  created (partitions=%s, replication=%s)\n" "$TOPIC" "$PARTITIONS" "$REPLICATION"
    fi
done

# ── Verify: list all user-defined topics ─────────────────────────────────────
echo ""
echo "───────────────────────────────────────────────────────────"
echo "  Verifying topics..."
echo "───────────────────────────────────────────────────────────"

docker compose -f "$COMPOSE_FILE" exec -T broker kafka-topics \
    --bootstrap-server localhost:9092 \
    --list 2>&1 | grep -v '_confluent' | grep -v '__' | grep -v '_schemas' | grep -v 'default' | grep -v 'docker-connect'

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Topic creation complete"
echo "═══════════════════════════════════════════════════════════"
