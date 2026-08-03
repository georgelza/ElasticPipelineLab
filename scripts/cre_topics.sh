#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   cre_topics.sh
#   Description           :   Create Kafka topics for the Elastic log pipeline
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Creates the Kafka topics used by the log analytics pipeline:
#       syslog-topic    — syslog-ng forwarded logs (Docker Compose)
#       filebeat-logs   — Filebeat (Docker Compose) + FluentBit (Kubernetes) logs
#       syslog-topic-*  — per-classification / per-security-segment topics
#
#   Usage: ./cre_topics.sh
#
#   Env: COMPOSE_PROJECT_NAME  Docker Compose project name  (default: elastic)
#        COMPOSE_FILE          Path to docker-compose.yml  (default: repo root)
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
    "syslog-topic:2:1"
    "filebeat-logs:2:1"
    "syslog-topic-filebeat-logs:2:1"
    "syslog-topic-prod-pci:2:1"
    "syslog-topic-prod-nonpci:2:1"
    "syslog-topic-prod-pci-ife:2:1"
    "syslog-topic-prod-nonpci-ife:2:1"
    "syslog-topic-nonprod-pci:2:1"
    "syslog-topic-nonprod-nonpci:2:1"
    "syslog-topic-nonprod-pci-ife:2:1"
    "syslog-topic-nonprod-nonpci-ife:2:1"
    "syslog-topic-prod-unregulated:2:1"
    "syslog-topic-nonprod-unregulated:2:1"
    "syslog-topic-network:2:1"
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
        syslog-topic*)
            # Syslog source streams: explicit delete policy + retention window.
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
