#!/usr/bin/env bash
################################################################################################################################
#
#   Project               :   Elasticsearch based Log Analytics deployment
#   File                  :   cre_topics.sh
#   Description           :   Create Kafka topics 
#   Version               :   v1.0.0
#   Author                :   George Leonard / georgelza@gmail.com
#
#   Creates the core Kafka topics used by the switch:
#       fraud_requests    — Phase 1 fraud scoring requests

#   Usage: ./cre_topics.sh
#
#   Env: COMPOSE_PROJECT_NAME  Docker Compose project name  (default: elastic)
#
################################################################################################################################
set -euo pipefail

VERSION="1.11.5"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-card8583}"

# Resolve docker compose file location
ROOT="${ROOT:-/Users/george/Desktop/MyDocs/Creator/card_switch_8583}"
COMPOSE_FILE="${ROOT}/docker-compose.yml"

# Format: "topic_name:partitions:replication_factor"
TOPICS=(
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
    "syslog-topic-filebeat-logs:2:1"
    "syslog-topic:2:1"
)

# sw_health / sw_stats / sw_conn are the inter-SIP bus topics — deliberately
# NOT compacted (see ToDo.md "Redis bus / Kafka bus" discussion): every
# message is retained for the full window below so the history sink
# (see history_sink.py or cre_history_sink_connector.sh) can replay from
# earliest and reconstruct trend history. Live consumers only care about the
# latest message per reporter (handled in application code, not the broker).
# 7 days gives the history sink plenty of room to catch up after any outage
# before messages age out — tune via BUS_RETENTION_MS if needed.
BUS_RETENTION_MS="${BUS_RETENTION_MS:-604800000}"   # 7 days

echo "═══════════════════════════════════════════════════════════"
echo "  Creating Kafka topics (project: ${COMPOSE_PROJECT_NAME})"
echo "═══════════════════════════════════════════════════════════"

for ENTRY in "${TOPICS[@]}"; do
    IFS=':' read -r TOPIC PARTITIONS REPLICATION <<< "$ENTRY"

    EXTRA_CONFIG=()
    case "$TOPIC" in
        syslog-topic|syslog-topic-filebeat-logs|syslog-topic-network)
            # Deliberately explicit: cleanup.policy=delete (not compact) +
            # a bounded retention window — see comment above TOPICS array.
            EXTRA_CONFIG=(--config "cleanup.policy=delete" --config "retention.ms=${BUS_RETENTION_MS}")
            ;;
    esac

    OUTPUT=$(
        if [ ${#EXTRA_CONFIG[@]} -gt 0 ]; then
            docker compose -f "$COMPOSE_FILE" exec broker kafka-topics \
                --create --topic "$TOPIC" \
                --bootstrap-server localhost:9092 \
                --partitions "$PARTITIONS" \
                --replication-factor "$REPLICATION" \
                "${EXTRA_CONFIG[@]}" 2>&1
        else
            docker compose -f "$COMPOSE_FILE" exec broker kafka-topics \
                --create --topic "$TOPIC" \
                --bootstrap-server localhost:9092 \
                --partitions "$PARTITIONS" \
                --replication-factor "$REPLICATION" 2>&1
        fi
    ) || true

    # Check if topic already exists
    if echo "$OUTPUT" | grep -qi "already exists"; then
        printf "  ✓ %-20s  already exists  (partitions=%s, replication=%s)\n" "$TOPIC" "$PARTITIONS" "$REPLICATION"
    else
        printf "  ✓ %-20s  created  (partitions=%s, replication=%s)\n" "$TOPIC" "$PARTITIONS" "$REPLICATION"
    fi
done

# ── Verify: list all user-defined topics ─────────────────────────────────────
# echo ""
# echo "───────────────────────────────────────────────────────────"
# echo "  Verifying topics..."
# echo "───────────────────────────────────────────────────────────"

# docker compose -f "$COMPOSE_FILE" exec broker kafka-topics \
#     --bootstrap-server localhost:9092 \
#     --list 2>&1 | grep -v '_confluent' | grep -v '__' | grep -v '_schemas' | grep -v 'default' | grep -v 'docker-connect'

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Topic creation complete"
echo "═══════════════════════════════════════════════════════════"
