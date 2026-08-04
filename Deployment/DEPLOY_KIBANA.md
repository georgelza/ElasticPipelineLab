# Kibana ↔ Elasticsearch Integration Guide

End-to-end documentation of how Kibana is wired into the Elastic log-analytics
stack on the `my-vc1` vcluster: service wiring, access, data views, saved
objects, dashboard provisioning and troubleshooting.

```
FluentBit / syslog-ng / Filebeat → Kafka (Compose)
        → ES Sink connector (Compose connect) → Elasticsearch (vcluster)
        → Kibana (vcluster) → browser (port-forward / Traefik)
```

## 1. Architecture / Service Wiring

| Piece | Where it runs | Manifest / service |
|:--- |:--- |:--- |
| Kibana 8.13.4 | vcluster `elastic` namespace | `k8s/2.01.kibana.yaml` → Deployment `kibana` + ClusterIP Service `kibana` |
| Elasticsearch | vcluster `elastic` namespace | `k8s/1.02.elasticsearch.yaml` → `elasticsearch-1`/`elasticsearch-2` + Service `elasticsearch` |
| Ingress | vcluster `ingress-traefik1` | `k8s/4.04.traefik-ingressroutes.yaml` → `/kibana` route |
| Kafka/Connect/S3 | Docker Compose (`elastic` project) | `docker-compose.yml` |

Key wiring facts:

- Kibana is a single-replica Deployment pointed at the in-cluster
  `http://elasticsearch:9200` (`server.host: 0.0.0.0`, `elasticsearch.hosts` in
  `k8s/2.01.kibana.yaml`). It resolves Elasticsearch via the Kubernetes DNS name
  `elasticsearch.elastic.svc` — no port-forwards involved on the server side.
- Kibana serves everything under **`server.basePath: "/kibana"`** with
  `server.rewriteBasePath: true` (`kibana.yml` in the ConfigMap). The Traefik
  `/kibana` IngressRoute does **not** strip the prefix — Kibana owns it. All
  API calls from the browser/curl must therefore include the `/kibana` prefix.
- Security is **disabled** on ES (`xpack.security.enabled: false`, homelab
  only), so Kibana needs no credentials and the APIs below need no auth.

## 2. Access

### 2.1 Direct port-forward (simplest)

```bash
kubectl port-forward service/kibana 5601:5601 -n elastic
# UI:    http://localhost:5601/kibana
# API:   http://localhost:5601/kibana/api/status
```

### 2.2 Through Traefik (recommended — one forward for everything)

```bash
kubectl port-forward service/traefik1 -n ingress-traefik1 8080:80
# Kibana UI: http://localhost:8080/kibana
# ES API:    http://localhost:8080/elasticsearch/_cluster/health
```

See `Deployment/TRAEFIK.md` for the ingress details.

> **basePath gotcha:** Kibana's REST API is *always* under `/kibana`. A request
> to `http://localhost:5601/api/...` (without the prefix) returns **404**;
> `http://localhost:5601/kibana/api/...` works.

## 3. Data Views (index patterns)

A **data view** is a saved object (`type: index-pattern`) that binds a Kibana
search/visualization/dashboard to one or more ES indices via a wildcard
`title` and a time field.

| Data view id | title (index pattern) | time field | Feed(s) |
|:--- |:--- |:--- |:--- |
| `logs-prod-nonpci` | `logs-prod-nonpci-*` | `@timestamp` | all feeds (created by `make elastic-setup`) |
| `logs-prod-nonpci-syslog` | `logs-prod-nonpci-syslog*` | `@timestamp` | syslog feed only |
| `logs-prod-nonpci-filebeat` | `logs-prod-nonpci-filebeat*` | `@timestamp` | filebeat feed only |
| `logs-prod-nonpci-fluentbit` | `logs-prod-nonpci-fluentbit*` | `@timestamp` | fluentbit feed only |

The per-feed views are provisioned by `make kibana-dashboards`
(`scripts/configure_kibana_dashboards.sh`) — see §5. They use
`allowNoIndex: true` so they exist even before the first document lands.

Create one manually (API):

```bash
curl -X POST "http://localhost:5601/kibana/api/saved_objects/index-pattern/logs-prod-nonpci-syslog" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"attributes":{"title":"logs-prod-nonpci-syslog*","timeFieldName":"@timestamp","allowNoIndex":"true"}}'
```

## 4. Saved Objects API — quick reference

Base URL: `http://localhost:5601/kibana/api/saved_objects` (always include
`/kibana`; always send the `kbn-xsrf: true` header on write requests).

| Operation | Method + path |
|:--- |:--- |
| Create one | `POST /api/saved_objects/{type}/{id}` |
| Bulk create (idempotent re-run friendly) | `POST /api/saved_objects/_bulk_create` |
| Find | `GET /api/saved_objects/_find?type=dashboard&search=...` |
| Export (NDJSON) | `POST /api/saved_objects/_export` |
| Import | `POST /api/saved_objects/_import` (multipart, `file=` + `overwrite=true`) |
| Delete | `DELETE /api/saved_objects/{type}/{id}` |

The saved-object model used by the dashboards script:

- **`index-pattern`** — data view (title pattern + time field).
- **`search`** — a saved Discover query; dashboard panels can embed it directly
  as a table (`kibanaSavedObjectMeta.searchSourceJSON` references the data view
  via `references[]`).
- **`visualization`** — an agg-based chart (`visState` JSON: aggs + params).
- **`dashboard`** — a grid of panels (`panelsJSON`); each panel references a
  visualization or search by id through `references[]` with the
  `{panelIndex}:panel_{panelIndex}` name convention.

`references[]` is mandatory — a dashboard whose panels reference objects
without corresponding `references[]` entries renders as broken panels.

## 5. Dashboard Provisioning

`make kibana-dashboards` runs `scripts/configure_kibana_dashboards.sh`, which:

1. Ensures ES + Kibana are reachable (starts the port-forwards if needed —
   the same logic as `scripts/configure_elastic.sh`).
2. Creates the three per-feed data views (§3) if missing.
3. For each feed, bulk-creates (idempotent — existing objects are left
   untouched):

   | Feed | Data view id | Saved search | Visualizations | Dashboard |
   |:--- |:--- |:--- |:--- |:--- |
   | Syslog | `logs-prod-nonpci-syslog` | latest events table | volume over time (histogram) + top programs (terms) | `dash-logs-prod-nonpci-syslog` |
   | Filebeat | `logs-prod-nonpci-filebeat` | latest events table | volume over time (histogram) + top hosts (terms) | `dash-logs-prod-nonpci-filebeat` |
   | FluentBit | `logs-prod-nonpci-fluentbit` | latest events table | volume over time (histogram) + stream split stdout/stderr (terms) | `dash-logs-prod-nonpci-fluentbit` |

The dashboards use `timeRestore: true` with `now-24h → now`, so they always
open on the last 24 h.

Open them in the UI: **Dashboard → search the dashboard title**
(e.g. "Syslog — Overview (prod-nonpci)").

### 5.1 Manual import/export (backup or UI-free sharing)

Export all three dashboards + their dependencies (NDJSON):

```bash
curl -X POST "http://localhost:5601/kibana/api/saved_objects/_export" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"objects":[{"type":"dashboard","id":"dash-logs-prod-nonpci-syslog"},{"type":"dashboard","id":"dash-logs-prod-nonpci-filebeat"},{"type":"dashboard","id":"dash-logs-prod-nonpci-fluentbit"}],"includeReferencesDeep":true}' \
  -o kibana-dashboards.ndjson
```

Import (after a `.kibana` wipe, e.g. post vcluster recovery):

```bash
curl -X POST "http://localhost:5601/kibana/api/saved_objects/_import?overwrite=true" \
  -H 'kbn-xsrf: true' -F "file=@kibana-dashboards.ndjson"
```

## 6. Index fields used by the dashboards

| Feed | Field | Type / notes |
|:--- |:--- |:--- |
| All | `@timestamp` | `date` (set by the `logs-template` index template; FluentBit renames `time`→`@timestamp`) |
| Syslog | `MESSAGE`, `HOST`, `PROGRAM`, `FACILITY`, `SEVERITY`, `ISODATE` | from syslog-ng `$(format-json --scope rfc5424 --scope nv-pairs --pair @timestamp=...)` |
| Filebeat | `message`, `host.hostname`, `log.file.path`, `source` (`docker-compose-filebeat`) | `add_host_metadata` processor; custom `fields.source` |
| FluentBit | `log` (CRI message body), `stream` (`stdout`/`stderr`), `source` (`k8s-fluent-bit`) | CRI parser `k8s/parsers.conf`; no kubernetes filter in `k8s/3.01.fluent-bit-config.yaml` |

Dynamic string fields map as `text` + `.keyword` (ES 8 default), so terms
aggregations use e.g. `PROGRAM.keyword`, `host.hostname.keyword`,
`stream.keyword`.

## 7. Snapshots & the prod-nonpci repository

Indices are snapshotted into the account's S3 repository by the `logs-slm` SLM
policy (daily 01:00 UTC, `logs-prod-nonpci-*` → `prod-nonpci`, retention
5–50/30d) and by the ad-hoc `make snapshot` target
(`scripts/take_snapshot.sh`). Kibana's own `.kibana_*` system indices are
**not** part of the log repository (they hold saved objects only and are
recreated by the deploy scripts). See `Deployment/DATASETS.md` for the
bucket/repo conventions.

## 8. Troubleshooting

- **Kibana shows "no data" in a data view**: confirm the ES index exists
  (`curl -s localhost:9200/_cat/indices/logs-prod-nonpci-*?v`), the sink
  connector is `RUNNING` (`curl -s localhost:8083/connectors/elasticsearch-sink/status`),
  and the data view's time field matches (`@timestamp`).
- **`/api/...` returns 404, `/kibana/api/...` works**: basePath — always
  prefix with `/kibana` (and keep `kbn-xsrf: true` on writes).
- **Dashboard panels say "Error" / "Could not locate that panel"**: the saved
  object references are broken — re-run `make kibana-dashboards` (it
  bulk-creates missing objects) or re-import the NDJSON export with
  `overwrite=true`.
- **Data view exists but aggregations fail on `.keyword` fields**: the index
  was created before the template applied, or fields were indexed with a
  different mapping — delete + re-create the index (the sink will re-populate
  it from the Kafka topic).
- **`.kibana` lost after vcluster recovery**: expected — data views and
  dashboards are code (`make elastic-setup` + `make kibana-dashboards`);
  re-run them after `make deployk8s`.
- **Kibana can't reach ES**: verify the ES Service exists and the Deployment
  env points at `http://elasticsearch:9200` (`kubectl get svc -n elastic`);
  check `kubectl logs deploy/kibana -n elastic`.
- **ES itself unhealthy ("broken node lock")**: see `Deployment/DEPLOY_ELASTIC.md`
  §10 and Todo §10 — typically the vcluster worker `/data` hostPath mounts are
  dangling after `./data/vc1` is deleted; recreate `data/vc1/n1..n3` and the
  vcluster, then re-apply `k8s/` + `make deployk8s`.

## 9. Related Documents

- `Deployment/DEPLOY_ELASTIC.md` — ES cluster + pipeline + sink connector
- `Deployment/TRAEFIK.md` — ingress layer (`/kibana`, `/elasticsearch` routes)
- `Deployment/DATASETS.md` — topics, indices, S3 buckets/repos, SLM
- `scripts/configure_elastic.sh` — ILM/template + combined data view
- `scripts/configure_kibana_dashboards.sh` — per-feed dashboards (this guide §5)
- `scripts/take_snapshot.sh` — ad-hoc `prod-nonpci` snapshots
