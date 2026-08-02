# Kubernetes Manifests for Elastic Stack

This directory contains all necessary Kubernetes manifests to deploy the Elastic stack:
1. Elasticsearch (StatefulSet)
2. Kibana (Deployment) 
3. FluentBit (DaemonSet)

## Deployment Sequence (as described in README.md):

### 1. Create Namespace: 
```bash
kubectl apply -f elastic-namespace.yaml
```

### 2. Create Elastic Storage (PV/PVC):
```bash
kubectl apply -f elasticsearch-pv.yaml
kubectl apply -f elasticsearch-pvc.yaml
```

### 3. Deploy Elasticsearch:
```bash
kubectl apply -f elasticsearch-config.yaml
kubectl apply -f elasticsearch-statefulset.yaml
kubectl apply -f elasticsearch-service.yaml
kubectl apply -f elasticsearch-headless-service.yaml
```

### 4. Deploy Kibana: 
```bash
kubectl apply -f kibana-config.yaml
kubectl apply -f kibana-deployment.yaml
kubectl apply -f kibana-service.yaml
```

### 5. Deploy FluentBit:
```bash
kubectl apply -f fluent-bit-config.yaml 
kubectl apply -f fluent-bit-daemonset.yaml
kubectl apply -f fluent-bit-service.yaml
```

## Details

All components deploy to the `elastic` namespace.

All Elasticsearch data is stored on a PersistentVolume mounted at `/data/elasticsearch`.

FluentBit is deployed as a DaemonSet to collect logs from containers via `/var/lib/docker/containers/` and forward them to Kafka through the `filebeat-logs` topic.