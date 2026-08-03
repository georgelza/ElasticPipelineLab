# Traefik Ingress — Access Layer

This document describes the Traefik v3 ingress layer that fronts the Elastic
log-analytics stack on the `my-vc1` vcluster.

## Overview

Traefik (`docker.io/traefik:v3.6.8`) runs as a single-replica Deployment in the
`ingress-traefik1` namespace. It uses the **Kubernetes CRD provider**
(`IngressRoute` / `Middleware`) with cross-namespace routing enabled, so it can
route to services in the `elastic` namespace (Kibana, Elasticsearch) as well as
the `monitoring` and `data` namespaces.

```
IngressRoute (ingress-traefik1)
        │  entryPoint: web (:80/8000)
        ├── /kibana          ──► kibana.elastic:5601        (no strip — Kibana owns /kibana)
        └── /elasticsearch   ──► elasticsearch.elastic:9200 (strip-elasticsearch middleware)
```

## Manifests

| File | Contents |
|------|----------|
| `k8s/07.traefik-crds.yaml` | Traefik v3 CRDs (`IngressRoute`, `Middleware`, `MiddlewareTCP`, ...) |
| `k8s/08.traefik-rbac.yaml` | `ingress-traefik1` namespace + ServiceAccount + ClusterRole/Binding |
| `k8s/09.traefik-deploy.yaml` | Traefik Deployment + ClusterIP Service (`traefik1`) |
| `k8s/10.traefik-ingressroutes.yaml` | Middlewares + IngressRoutes (incl. Kibana + ES routes) |

## Entrypoints

Configured on the Deployment args:

| Entrypoint | Container port | Service port | Purpose |
|------------|----------------|--------------|---------|
| `web` | 8000 | 80 | Main HTTP routes (`/kibana`, `/elasticsearch`, ...) |
| `websecure` | 8443 | 443 | HTTPS (TLS enabled) |
| `rustfs-console` | 9001 | 9001 | RustFS console UI at `/` |
| `metrics` | 9100 | — | Prometheus `/metrics` |
| `traefik` | 8080 | — | Traefik dashboard + `/ping` |

The `traefik1` Service is `ClusterIP` — there is **no LoadBalancer**, so all
access goes through `kubectl port-forward`.

## Access

```bash
# Main ingress (all /kibana, /elasticsearch, ... routes)
kubectl port-forward service/traefik1 -n ingress-traefik1 8080:80

# RustFS console
kubectl port-forward service/traefik1 -n ingress-traefik1 9001:9001
```

Then:

- Kibana UI → `http://localhost:8080/kibana`
- ES REST API → `http://localhost:8080/elasticsearch/`

> Kibana is served under `server.basePath: /kibana` with
> `server.rewriteBasePath: true` — the `/kibana` prefix is **not** stripped by
> Traefik (Kibana handles it internally). Elasticsearch, in contrast, uses the
> `strip-elasticsearch` middleware (stripPrefix `/elasticsearch`).

## Verification

```bash
# Traefik up?
kubectl get pods -n ingress-traefik1
kubectl rollout status deployment/traefik1 -n ingress-traefik1

# Cluster health through the ingress (after port-forward 8080:80)
curl -s http://localhost:8080/elasticsearch/_cluster/health?pretty

# Kibana status through the ingress
curl -s http://localhost:8080/kibana/api/status

# IngressRoutes
kubectl get ingressroute -n ingress-traefik1
kubectl get middleware -n ingress-traefik1
```

## Notes / Gotchas

- Cross-namespace routing requires
  `--providers.kubernetescrd.allowCrossNamespace=true` (set in
  `k8s/09.traefik-deploy.yaml`).
- Traefik RBAC (`k8s/08.traefik-rbac.yaml`) must include `endpointslices`,
  `configmaps`, `nodes`, `services` and the `traefik.io` CRD resources, or the
  routes will not resolve.
- Kibana's basePath must match the ingress path — if `server.basePath` changes,
  update the IngressRoute match accordingly.
- The Elasticsearch REST API is exposed unauthenticated on purpose for this
  homelab deployment (security is disabled in `k8s/02.elasticsearch.yaml`).
