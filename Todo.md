# Todo — Elastic Log Analytics Pipeline

Tracking list for the Elastic log-analytics deployment (vcluster `my-vc1` +
Docker Compose Kafka stack). Keep statuses updated as tasks complete.

Legend: `[ ]` pending · `[x]` done · `[~]` in progress

---

## 1. Documentation

- [x] Add `Todo.md` (this file)
- [x] Rewrite `Deployment/DEPLOY_ELASTIC.md` to describe the current
      **multi-node (2 × Deployment) Elasticsearch** stack (was: outdated single-node
      StatefulSet + security-enabled config that no longer exists)
- [x] Add `Deployment/TRAEFIK.md` documenting the Traefik ingress layer
      (`ingress-traefik1` namespace, IngressRoutes, middlewares, port-forwards)
- [x] Update `Deployment/DEPLOY_SYSLOG.md` to reflect the fixed
      `syslog-ng → Kafka` wiring (`broker:29092`, JSON `format-json` payloads)

## 2. Kafka → Elasticsearch Sink Connector (part of deployment)

- [x] Add ES sink connector configuration as deployment artefacts
      (`scripts/configure_es_sink.sh` + connector JSON payload)
- [x] Wire sink configuration into the root `Makefile` (`make sink`, and
      automatically as the last step of `make deployk8s`)
- [x] Document the required ES reachability from the Compose `connect` container
      (port-forward + `host.docker.internal`) in the docs

## 3. Elastic/Kibana configuration for the syslog stream

- [x] Create ES ILM policy + index template for `logs-*` / `filebeat-*`
      (`scripts/configure_elastic.sh`)
- [x] Create Kibana data views for the syslog + fluent-bit streams
- [x] Ensure `action.auto_create_index` covers `logs-*` and `filebeat-*`
      (already set in `k8s/02.elasticsearch.yaml`)

## 4. syslog → syslog-ng → Kafka as part of the Docker Compose deployment

- [x] Fix `data/syslog-ng/config/syslog-ng.conf` Kafka destination
      (`bootstrap_servers` pointed at `connect:8083` — wrong; now `broker:29092`)
- [x] Add canonical config at `infrastructure/syslog-ng/syslog-ng.conf` and have
      `make run` provision it into `./data/syslog-ng/config/`
- [x] Fix `docker-compose.yml` `syslog-ng.depends_on` (`connect` → `broker`)
- [x] Emit JSON payloads from syslog-ng so the ES sink `JsonConverter` can parse
      them (`$(format-json)`)

## 5. FluentBit → Kafka verification

- [x] Confirm whether FluentBit already publishes to Kafka
      **Yes** — `k8s/04.fluent-bit-config.yaml` `[OUTPUT] kafka` → topic
      `filebeat-logs`, brokers `broker:29092` (resolved via `hostAliases`
      `172.20.0.2` in `k8s/05.fluent-bit-daemonset.yaml`), JSON format, with
      `timestamp → @timestamp` rename filter.
- [ ] (Operational) Verify end-to-end: Kafka topic → sink connector → ES index
      `logs-filebeat` → Kibana data view shows documents.

## 6. Makefile

- [x] `make run` provisions `syslog-ng.conf` and starts the Compose stack
- [x] `make deployk8s` — apply `k8s/`, wait for rollouts, then configure ES
      (ILM/templates), then configure the Kafka ES sink connector
- [x] `make sink` / `make elastic-setup` standalone re-runnable targets

## 7. Remaining / next steps

- [ ] End-to-end smoke test (start a syslog sender, verify `logs-syslog` index)
- [ ] Review `Deployment/DEPLOY_FILEBEAT*.md`, `DATASETS.md`, `ALERTS.md`,
      `DEPLOY_NG_FEED.md`, `FLUENTBIT_SELECTIVE_INGEST.md` for stale references
      (StatefulSet / single-node / security-on) and align if needed
