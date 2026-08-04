# Infrastructure

Build-time and canonical-configuration artefacts for the Docker Compose side of
the Elastic log-analytics pipeline (Kafka, Kafka Connect, syslog-ng). The
Kubernetes side (`k8s/`) is deployed separately into the `my-vc1` vcluster; the
two sides meet at `host.docker.internal` (Compose → vcluster) and
`broker:29092` (vcluster → Compose Kafka), see `Deployment/DEPLOY_ELASTIC.md`.

```
infrastructure/
├── .env                 # Build-time variables (REPO_NAME for image tagging)
├── Makefile             # make pull (source images) / make build (connect image)
├── connect/
│   ├── Dockerfile       # kafka-connect-custom:3.3 image definition
│   └── Makefile         # make build → georgelza/kafka-connect-custom:3.3
└── syslog-ng/
    └── syslog-ng.conf   # Canonical syslog-ng config (Kafka JSON output)
```

## connect/ — Kafka Connect ES sink image

The sink connector runs inside the Compose `connect` service
(`docker-compose.yml` → `image: georgelza/kafka-connect-custom:3.3`). That image
is built from this directory:

- `connect/Dockerfile` — `FROM confluentinc/cp-server-connect-base:7.9.6`, then
  installs the Elasticsearch connector plugin via
  `confluent-hub install --no-prompt confluentinc/kafka-connect-elasticsearch:latest`.
- `connect/Makefile` — tags the image `${REPO_NAME}/kafka-connect-custom:${VERSION}`
  (`REPO_NAME` from `infrastructure/.env`, `VERSION=3.3`).

Build once, before first `make run`:

```bash
cd infrastructure && make build
docker images | grep kafka-connect-custom   # georgelza/kafka-connect-custom:3.3
```

The connector itself (`elasticsearch-sink`, `topics.regex: logs-prod-nonpci-.*`,
target `host.docker.internal:9200`) is registered by
`scripts/configure_es_sink.sh` — see `Deployment/DEPLOY_ELASTIC.md` §6.

## syslog-ng/ — canonical syslog-ng configuration

`syslog-ng/syslog-ng.conf` is the canonical source for the syslog-ng feed. It is
copied into `data/syslog-ng/config/syslog-ng.conf` during provisioning
(`make run` in the repo root), where the Compose `syslog-ng` service mounts it:

- inputs: UDP `0.0.0.0:5514` (published as `514/udp`) and TCP `0.0.0.0:6601`
  (published as `601/tcp`)
- output: Kafka destination (`broker:29092`) on topic
  `logs-prod-nonpci-syslog`, JSON-formatted via
  `$(format-json --scope rfc5424 --scope nv-pairs --pair @timestamp=...)`

Full walkthrough: `Deployment/DEPLOY_NG_FEED.md`.

## Makefile targets

| Target  | Action |
|:--- |:--- |
| `make pull` | Pull all source images (Confluent 7.9.6 set, rustfs, syslog-ng, filebeat 8.14.0) |
| `make build` | Build `georgelza/kafka-connect-custom:3.3` from `connect/` |

## .env

`infrastructure/.env` holds build-time variables:

- `REPO_NAME` — registry namespace for the custom connect image (consumed by
  `connect/Makefile`).
- The `S3_*` values present here are **legacy leftovers** from an earlier
  approach and are **not** consumed anywhere. Snapshot/S3 configuration is
  driven by the repo-root `.env` + `scripts/configure_s3_snapshots.sh` (see
  `Deployment/DATASETS.md`).
