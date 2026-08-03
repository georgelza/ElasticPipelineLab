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
      (already set in `k8s/1.02.elasticsearch.yaml`)

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
      **Yes** — `k8s/3.01.fluent-bit-config.yaml` `[OUTPUT] kafka` → topic
      `logs-prod-nonpci-fluentbit`, brokers `broker:29092` (resolved in-cluster
      via the `broker` ExternalName Service, `k8s/1.04.external-services.yaml`,
      which aliases `host.docker.internal:29092` — the Docker Desktop host
      alias, published port; no hardcoded compose-bridge IPs, with
      `rdkafka.broker.address.family v4` to bypass the unroutable IPv6
      gateway), JSON format, with `timestamp → @timestamp` rename filter.
- [x] (Operational) Verify end-to-end: Kafka topic → sink connector → ES index
      `logs-prod-nonpci-filebeat` → Kibana data view shows documents.
      **Verified** — the full pipeline is live:
      - FluentBit on vcluster nodes tails `/var/log/containers/*.log` (CRI
        parser in `k8s/parsers.conf`; the old `/var/lib/docker/containers` path
        does not exist on k3s/containerd nodes and was removed) and publishes
        k8s pod logs (e.g. `ingress-traefik1`) into `logs-prod-nonpci-fluentbit`.
      - Compose Filebeat publishes host logs into `logs-prod-nonpci-filebeat` (mount
        fixed to `./data/filebeat/config/filebeat.yml`, service added to
        `make run`).
      - Sink connector `elasticsearch-sink` (RUNNING) subscribes to the whole
        `logs-prod-nonpci-*` family via `topics.regex: logs-prod-nonpci-.*` and writes
        each topic into a same-named index (this connector version ignores the
        old `topic.index.map`; the `logs-<account>-<source>` naming convention
        makes any per-topic mapping unnecessary).
      - ~425k docs re-streamed into `logs-prod-nonpci-filebeat`; fresh syslog
        messages land in `logs-prod-nonpci-syslog` with `@timestamp`; the Kibana
        data view `logs-prod-nonpci*` shows documents.
- [x] Fix the syslog-ng container so it pushes **directly** to Kafka (no
      file/Filebeat hop): the `linuxserver/syslog-ng` image has no Kafka module,
      so `docker-compose.yml` now uses the official `balabit/syslog-ng` image
      (native `kafka()` destination, `message('$(format-json ...)')` body).
      The previous file-hop workaround (syslog-ng → JSON file → Filebeat) was
      reverted.

## 6. Makefile

- [x] `make run` provisions `syslog-ng.conf` and starts the Compose stack
- [x] `make deployk8s` — apply `k8s/`, wait for rollouts, then configure ES
      (ILM/templates), then configure the Kafka ES sink connector, then the
      RustFS S3 snapshot repositories + SLM policy (`make s3-snapshots`)
- [x] `make sink` / `make elastic-setup` standalone re-runnable targets
- [x] Sink/ES scripts leave a **persistent** ES port-forward running
      (`/tmp/es-pf.pid`, nohup) so the connector can keep reaching ES at
      `host.docker.internal:9200` after the script exits
      (stop with `pkill -f "port-forward service/elasticsearch"`)

## 7. Remaining / next steps

- [x] End-to-end smoke test (start a syslog sender, verify `logs-prod-nonpci-syslog`
      index) **Done** — UDP/TCP syslog via port 514/601 → `logs-prod-nonpci-syslog`
      → `logs-prod-nonpci-syslog` verified.
- [x] Standardise Kafka topic naming to `logs-<account>-<source>`
      (logs-prod-nonpci-syslog, logs-prod-nonpci-filebeat,
      logs-prod-nonpci-fluentbit, logs-prod-nonpci-log4j) so the
      sink connector subscribes with a `logs-prod-nonpci-.*` wildcard (see
      `scripts/cre_topics.sh`, `scripts/configure_es_sink.sh`,
      syslog-ng/filebeat/fluent-bit configs).
- [ ] Review `Deployment/DEPLOY_FILEBEAT*.md`, `DATASETS.md`, `ALERTS.md`,
      `DEPLOY_NG_FEED.md`, `FLUENTBIT_SELECTIVE_INGEST.md` for stale references
      (StatefulSet / single-node / security-on / file-hop) and align if needed

## 8. Elasticsearch S3 snapshot offload (RustFS)

- [x] Diagnose and fix `PUT _snapshot/rustfs-backup` verification failure
      **Done** — root cause: ES 8.13's repository-s3 does **not** read
      `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars; its fallback
      credential chain is the EC2 instance-metadata provider only
      (`EC2ContainerCredentialsProviderWrapper` → 169.254.169.254 →
      "Connection refused"). Fixed by pre-seeding an ES **keystore** with
      `s3.client.default.access_key` / `secret_key` (Secret `es-s3-keystore`,
      mounted read-only into both pods — see `k8s/1.03.es-s3-credentials.yaml`,
      `k8s/1.02.elasticsearch.yaml`). Verified end-to-end: snapshot →
      `my-log-bucket` → shards written (9/9).
- [x] Add `scripts/configure_s3_snapshots.sh` registering the **eight
      security-classification repositories** — one per account/bucket
      (`prod-pci`, `prod-nonpci`, `prod-unregulated`, `prod-ife`,
      `nonprod-pci`, `nonprod-nonpci`, `nonprod-unregulated`, `nonprod-ife`;
      IFE = Internet Facing Exposed) — with the S3 bucket name
      mapping 1:1 to the AWS account name and the repository sharing the same
      name as the bucket. Base path follows the convention
      `<project>/year=yyyy/month=mm/day=dd/<instance>` inside each bucket
      (account == bucket; project first, date segments zero-padded `%Y/%m/%d`),
      plus the `logs-slm` SLM policy (daily 01:00 UTC, `logs-prod-nonpci-*` →
      `prod-nonpci`, retention 5–50/30d). Re-runnable/idempotent.
- [x] Wire `make s3-snapshots` into the Makefile (standalone target + last step
      of `make deployk8s`); fix `apply-k8s-layer` to use the **quoted** glob
      `kubectl apply -f "k8s/$(LAYER).*"` (shell-expanded globs are rejected by
      kubectl).
- [x] Document the eight buckets + path convention + SLM policy in
      `Deployment/DATASETS.md`; document the 5 deployment layers
      (Layer 0 Docker Compose + Layers 1–4 k8s) in `README.md`.
- [x] Cleanup: removed the legacy `rustfs-backup` repo / `test-1` snapshot and
      orphaned objects from `my-log-bucket`; canonical state = exactly the eight
      classification repositories.
