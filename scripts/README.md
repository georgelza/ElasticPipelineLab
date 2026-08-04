# Scripts

Deployment/operational automation for the Elastic log-analytics pipeline. Every
script is idempotent (safe to re-run) and is normally invoked through the
repo-root `Makefile` target listed below. All paths are relative to the repo
root; `kubectl`-based scripts reuse a shared `kubectl port-forward` on port
`9200` (pid file `/tmp/es-pf.pid`).

| Script | Purpose | Make target | Key env vars (default) |
|:--- |:--- |:--- |:--- |
| `configure_elastic.sh` | ES ILM policy + index templates (`logs-*`, `@timestamp` time field) + Kibana data view (`logs-prod-nonpci-*`) | `make elastic-setup` | `ES_NAMESPACE` (`elastic`), `KIBANA_BASE` (`/kibana`) |
| `configure_es_sink.sh` | Register/update the `elasticsearch-sink` Kafka Connect connector (`topics.regex: logs-prod-nonpci-.*` → same-named indices via `host.docker.internal:9200`) | `make sink` | `CONNECT_URL` (`http://localhost:8083`), `ES_PF_PORT` (`9200`), `ES_NAMESPACE` (`elastic`), `CONNECTOR` (`elasticsearch-sink`) |
| `configure_kibana_dashboards.sh` | Provision Kibana saved objects for the 3 log feeds: index patterns, saved searches, visualizations, dashboards | `make kibana-dashboards` | `ES_NAMESPACE` (`elastic`), `KIBANA_BASE` (`/kibana`) |
| `configure_s3_snapshots.sh` | Create the 8 classification S3 buckets (RustFS) + per-account ES snapshot repositories + SLM policy `logs-slm` (daily 01:00 UTC) | `make s3-snapshots` | `ES_NAMESPACE` (`elastic`), `RUSTFS_ENDPOINT` (`http://127.0.0.1:9000`), `SLM_REPOSITORY` (`prod-nonpci`), `SLM_INDICES` (`logs-prod-nonpci-*`) |
| `cre_topics.sh` | Create the `logs-prod-nonpci-{syslog,filebeat,fluentbit,log4j}` Kafka topics (2 partitions, cleanup policy `delete`, 7-day retention) | `make createtopics` | `COMPOSE_PROJECT_NAME` (`elastic`), `COMPOSE_FILE` (repo root) |
| `setup_macos_syslog.sh` | Host-side: point macOS syslog at the Compose syslog-ng (`localhost:514`) | — | — |
| `setup_macos_filebeat.sh` | Host-side: macOS Filebeat → Compose Kafka (`localhost:9092`, topic `logs-prod-nonpci-filebeat`) | — | — |
| `take_snapshot.sh` | Ad-hoc ES snapshot of `logs-prod-nonpci-*` into the `prod-nonpci` repo (waits for completion, verifies `SUCCESS`) | `make snapshot` | `ES_NAMESPACE` (`elastic`), `SNAPSHOT_REPO` (`prod-nonpci`), `SNAPSHOT_INDICES` (`logs-prod-nonpci-*`) |

## Typical deploy sequence

```bash
make deployk8s            # elastic-setup → kibana-dashboards → sink → s3-snapshots
make createtopics         # Kafka topics (after compose recovery)
make snapshot             # ad-hoc snapshot of logs-prod-nonpci-*
```

## Convention

Topics, ES indices and snapshot repositories all follow
`logs-<account>-<source>` / per-account naming (currently a single simulated
account: `prod-nonpci`). See the header of each script and
`Deployment/DATASETS.md` for the full accounting model.
