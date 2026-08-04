# Kubernetes Manifests

This directory is the single deployment source for the Elastic stack on the
`my-vc1` vcluster (see `../vcluster.yml`).

Manifests are grouped into **layers** by component. The first digit is the
layer (1 = Elasticsearch, 2 = Kibana, 3 = FluentBit, 4 = Traefik); the second
digit is the apply order *within* that layer (zero-padded so 10 sorts after 2).

## Layer Map

| Layer | Prefix | What it deploys |
|:--- |:--- |:--- |
| 1 — Elastic | `1.*` | `elastic` namespace + PVs/PVCs + Elasticsearch (2-node cluster) |
| 2 — Kibana | `2.*` | Kibana Deployment + Service (basePath `/kibana`) |
| 3 — FluentBit | `3.*` | FluentBit ConfigMap + DaemonSet + metrics Service |
| 4 — Traefik | `4.*` | Traefik v3 CRDs + RBAC + Deployment + IngressRoutes |

## Files

| # | File | What it deploys |
|:--- |:--- |:--- |
| 1.00 | `1.00.elastic-namespace.yaml` | `elastic` namespace |
| 1.01 | `1.01.elastic-storage.yaml` | PVs + PVCs for both ES nodes: `elasticsearch-pv-1`/`elasticsearch-data-1` (`/data/elasticsearch`) and `elasticsearch-pv-2`/`elasticsearch-data-2` (`/data/elasticsearch-2`) |
| 1.02 | `1.02.elasticsearch.yaml` | ES ConfigMap + 2 Deployments (`elasticsearch-1` → es-1/worker-1, `elasticsearch-2` → es-2/worker-2) + load-balancer & headless Services — one 2-node cluster |
| 2.01 | `2.01.kibana.yaml` | Kibana ConfigMap + Deployment + Service (8.13.4, basePath `/kibana`) |
| 3.01 | `3.01.fluent-bit-config.yaml` | FluentBit config (tail → Kafka `logs-prod-nonpci-fluentbit`) |
| 3.02 | `3.02.fluent-bit-daemonset.yaml` | FluentBit DaemonSet |
| 3.03 | `3.03.fluent-bit-service.yaml` | FluentBit metrics service (2020) |
| 4.01 | `4.01.traefik-crds.yaml` | Traefik v3 CRDs (IngressRoute, Middleware, ...) |
| 4.02 | `4.02.traefik-rbac.yaml` | `ingress-traefik1` namespace + ServiceAccount + RBAC |
| 4.03 | `4.03.traefik-deploy.yaml` | Traefik Deployment + Service |
| 4.04 | `4.04.traefik-ingressroutes.yaml` | Middlewares + IngressRoutes (kibana, elasticsearch, ...) |

## Deploy Everything

```bash
kubectl apply -f k8s/
```

## Deploy by Layer

Apply a whole layer with a glob (shell expands it):

```bash
kubectl apply -f k8s/1.*     # Elastic: namespace + storage + Elasticsearch
kubectl apply -f k8s/2.*     # Kibana
kubectl apply -f k8s/3.*     # FluentBit
kubectl apply -f k8s/4.*     # Traefik
```

Or step-by-step within a layer:

```bash
kubectl apply -f k8s/1.00.elastic-namespace.yaml
kubectl apply -f k8s/1.01.elastic-storage.yaml
kubectl apply -f k8s/1.02.elasticsearch.yaml
kubectl apply -f k8s/2.01.kibana.yaml
kubectl apply -f k8s/3.01.fluent-bit-config.yaml
kubectl apply -f k8s/3.02.fluent-bit-daemonset.yaml
kubectl apply -f k8s/3.03.fluent-bit-service.yaml
kubectl apply -f k8s/4.01.traefik-crds.yaml
kubectl apply -f k8s/4.02.traefik-rbac.yaml
kubectl apply -f k8s/4.03.traefik-deploy.yaml
kubectl apply -f k8s/4.04.traefik-ingressroutes.yaml
```

> Layer 1 creates the `elastic` namespace that layers 2–3 deploy into, and
> layer 4's IngressRoutes target the Kibana/ES Services from layers 1–2 — so
> apply the layers in dependency order (1 → 2 → 3 → 4) when going layer by
> layer.

## Details

- All Elastic components deploy to the `elastic` namespace.
- Elasticsearch runs as a **2-node cluster** (production-style simulation):
  - `es-1` — Deployment `elasticsearch-1` on `worker-1`, PVC `elasticsearch-data-1`
    (hostPath `/data/elasticsearch` → `./data/vc1/n1/elasticsearch`).
  - `es-2` — Deployment `elasticsearch-2` on `worker-2`, PVC `elasticsearch-data-2`
    (hostPath `/data/elasticsearch-2` → `./data/vc1/n2/elasticsearch-2`).
  - Both pods share the `app: elasticsearch` label, so the `elasticsearch` Service
    and the Traefik ingress load-balance across both nodes; the headless
    `elasticsearch-headless` Service is used for node discovery.
  - Node identity is set per pod (`node.name` env), discovery is multi-node via
    `discovery.seed_hosts` + `cluster.initial_master_nodes` (ES Java heap is
    `-Xms1g -Xmx1g` to pass the multi-node bootstrap heap check).
- All data persistence sits under `./data/`.
- Kibana is served under the `/kibana` base path (`server.basePath: /kibana`) for
  the Traefik ingress.
- FluentBit is deployed as a DaemonSet to collect container logs and forward them
  to Kafka through the `logs-prod-nonpci-fluentbit` topic.

## Port Forwards (direct, without ingress)

### Elasticsearch

```bash
kubectl port-forward service/elasticsearch 9200:9200 -n elastic
```

### Kibana

```bash
kubectl port-forward service/kibana 5601:5601 -n elastic
# browse http://localhost:5601/kibana
```

## Port Forwards (via Traefik ingress)

```bash
kubectl port-forward service/traefik1 -n ingress-traefik1 8080:80
```

- http://localhost:8080/kibana → Kibana
- http://localhost:8080/elasticsearch/_cluster/health → Elasticsearch REST API
