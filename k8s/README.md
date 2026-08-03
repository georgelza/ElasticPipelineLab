# Kubernetes Manifests

This directory is the single deployment source for the Elastic stack on the
`my-vc1` vcluster (see `../vcluster.yml`).

Files are numbered in the order they must be applied — `kubectl apply -f k8s/`
applies them in correct deployment order (zero-padded so 10 sorts after 9).

## Deployment Order

| # | File | What it deploys |
|---|------|-----------------|
| 00 | `00.elastic-namespace.yaml` | `elastic` namespace |
| 01 | `01.elastic_storage.yaml` | PVs + PVCs for both ES nodes: `elasticsearch-pv`/`elasticsearch-data` (`/data/elasticsearch`) and `elasticsearch-pv-2`/`elasticsearch-data-2` (`/data/elasticsearch-2`) |
| 02 | `02.elasticsearch.yaml` | ES ConfigMap + 2 Deployments (`elasticsearch-1` → es-1/worker-1, `elasticsearch-2` → es-2/worker-2) + load-balancer & headless Services — one 2-node cluster |
| 03 | `03.kibana.yaml` | Kibana ConfigMap + Deployment + Service (8.13.4, basePath `/kibana`) |
| 04 | `04.fluent-bit-config.yaml` | FluentBit config (tail → Kafka `filebeat-logs`) |
| 05 | `05.fluent-bit-daemonset.yaml` | FluentBit DaemonSet |
| 06 | `06.fluent-bit-service.yaml` | FluentBit metrics service (2020) |
| 07 | `07.traefik-crds.yaml` | Traefik v3 CRDs (IngressRoute, Middleware, ...) |
| 08 | `08.traefik-rbac.yaml` | `ingress-traefik1` namespace + ServiceAccount + RBAC |
| 09 | `09.traefik-deploy.yaml` | Traefik Deployment + Service |
| 10 | `10.traefik-ingressroutes.yaml` | Middlewares + IngressRoutes (kibana, elasticsearch, ...) |

## Deploy Everything

```bash
kubectl apply -f k8s/
```

Or step-by-step:

```bash
kubectl apply -f k8s/00.elastic-namespace.yaml
kubectl apply -f k8s/01.elastic_storage.yaml
kubectl apply -f k8s/02.elasticsearch.yaml
kubectl apply -f k8s/03.kibana.yaml
kubectl apply -f k8s/04.fluent-bit-config.yaml
kubectl apply -f k8s/05.fluent-bit-daemonset.yaml
kubectl apply -f k8s/06.fluent-bit-service.yaml
kubectl apply -f k8s/07.traefik-crds.yaml
kubectl apply -f k8s/08.traefik-rbac.yaml
kubectl apply -f k8s/09.traefik-deploy.yaml
kubectl apply -f k8s/10.traefik-ingressroutes.yaml
```

> Note: the Elasticsearch + Kibana workloads and the Traefik ingress previously
> lived under `deps/1.elasticsearch` and `deps/3.traefik-ingress`; they have been
> moved here (namespace renamed `logging` → `elastic`) and the `deps/` directory
> has been removed.

## Details

- All Elastic components deploy to the `elastic` namespace.
- Elasticsearch runs as a **2-node cluster** (production-style simulation):
  - `es-1` — Deployment `elasticsearch-1` on `worker-1`, PVC `elasticsearch-data`
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
  to Kafka through the `filebeat-logs` topic.

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
