# ElasticSearch Stack Log Analytics Pipeline

This repository contains the complete deployment configuration for an [Elastic Stack](https://www.elastic.co) log analytics pipeline. 

The solution includes [Syslog](https://en.wikipedia.org/wiki/Syslog) forwardig onto [Syslog-ng](https://en.wikipedia.org/wiki/Syslog-ng), [Fluentbit](https://fluentbit.io) and [Filebeat](https://www.elastic.co/beats/filebeat) part of the [Beats framework](https://www.elastic.co/beats) of lightweight data shippers, all configured to publish to [Kafka](https://kafka.apache.org) topics.

Our Topics to be utlise the [Kafka Connect](https://www.confluent.io/lp/confluent-connectors/) framework via Kafka Sink Connector jobs, persisting our log streams into [ElasticSearch](https://www.elastic.co), enabling comprehensive log collection and analysis solution.


Just to make it clear, all of this is being done on my Apple Macbook, and to put it simply, this would be impossible without what [vCluster](https://www.vcluster.com) allows me to do as far as running a local [Kubernetes](https://kubernetes.io) cluster is concerned.

I'm simulating the off cluster supporting services via [Docker Compose](https://docs.docker.com/compose/).

## Architecture Overview

The deployment follows a modern log analytics architecture with the following components:

### Core Stack

- **Elasticsearch**: Distributed search and analytics engine for log storage, little known fact, it's a Vector database at it's core, as such allows for  much wider set of use cases. 
- **Kibana**: Web interface for data visualization and exploration
- **Filebeat**: Lightweight log shipper, for our use case, for Kubernetes pod logs

### Log Collection

- **Syslog**: Standard syslog protocol support
- **Syslog-ng**: Enhanced syslog implementation with advanced filtering
- **FluentBit**: Kubernetes-native log collection (for containers)
- **OS-level Syslog**: Direct-on-OS syslog collector
- **OS-level Filebeat**: Direct-on-OS Filebeat collector

### Integration Layer

- **Kafka**: Message broker for log ingestion and buffering
- **Kafka Connect**: Connector for Elasticsearch sink integration
- **RustFS**: S3 tiered storage solution for long-term log retention

## Troubleshooting

### Docker Images Not Found During `make run`
If you encounter errors like:
```
Error response from daemon: pull access denied for elastic/rustfs, repository does not exist or may require 'docker login': denied
```

This occurs because custom Docker images (`elastic/rustfs`, `elastic/kafka-connect-custom`) are not available in public registries. You must first build these images using:

```bash
make build
```

This will build all required Docker images including the custom Kafka Connect and RustFS containers needed for proper operation.

### Deployment Order
When using both Docker Compose (for Kafka infrastructure) and Kubernetes (for Elasticsearch/Dashboard):
1. First run `make build` to build all required Docker images
2. Then run `make run` to start the Docker Compose services
3. Finally run `make k8s` to deploy Kubernetes components

The Docker Compose infrastructure (Kafka, Connect, etc.) must be running before deploying Kubernetes components.


### Project Git

[Elastic Pipeline Lab](https://github.com/georgelza/ElasticPipelineLab)

---

## Deployment Flow

The Below is the world of the possible..., we will be deploying most, except for the various Log4J input feeds and AI Integration consumption.

```mermaid
graph TD
    A[Syslog Sources] --> B[Syslog-NG Forwarder] 
    C[Filebeat - K8s Agents] --> X[Kafka Topic]
    D[K8s Deployments] --> H
    Y[Log4J] --> X
    M[Log4J] --> L
    I[OS-level Syslog] --> X
    J[OS-level Filebeat] --> X
    L[OS-Level Filebeat] --> X
    H[FluentBit] --> X
    B --> X
    X --> E[Kafka Connect]
    E --> F[Elasticsearch]
    F --> K[S3 Object Store]
    F --> G[Kibana UI]
    F --> N[AI Model]
```

---

## Architecture Diagrams

### 1. High-level Architecture

![Architecture Overview](diagrams/architecture.png)

### 2. Docker Compose Infrastructure

![Docker Compose Stack](diagrams/DockerCompose.svg)

### 3. Kubernetes Elastic Stack Deployment

![Kubernetes Log Analytics Stack](diagrams/K8s.svg)

---

## Deployment Layers

The stack is split into five layers. **Layer 0** runs in Docker Compose on the
host (off-cluster supporting services); **Layers 1–4** are Kubernetes manifests
under `k8s/`, applied by numeric prefix so each layer can be applied (or
updated) independently.

### Layer 0 — Docker Compose infrastructure (`make run`)

Off-cluster supporting services, all on the `elastic` Docker bridge network
(172.20.0.0/16). The vcluster pods reach them through **published-port DNAT**
plus `hostAliases` (the same pattern FluentBit uses for the Kafka broker).

| Service | Container | Publish | Purpose |
|---|---|---|---|
| `broker` | Kafka | `9092/9093` | `logs-prod-nonpci-*` topics (`logs-prod-nonpci-syslog`, `logs-prod-nonpci-filebeat`, `logs-prod-nonpci-fluentbit`, `logs-prod-nonpci-log4j`) |
| `schema-registry` | Confluent Schema Registry | `8081` | Kafka schemas |
| `control-center` | Confluent Control Center | `9021` | Kafka Connect UI |
| `connect` | Kafka Connect | `8083` | ES sink connector (`elasticsearch-sink`) |
| `syslog-ng` | balabit/syslog-ng | `514/601` | UDP/TCP syslog → `logs-prod-nonpci-syslog` (JSON `format-json`) |
| `filebeat` | Elastic Filebeat | – | host logs → `logs-prod-nonpci-filebeat` |
| `rustfs` | RustFS (S3) | `9000` S3 API / `9001` console | snapshot object store (eight classification buckets) |

### Layer 1 — Elasticsearch (`kubectl apply -f "k8s/1.*"`)

| File | Contents |
|---|---|
| `1.00.elastic-namespace.yaml` | `elastic` namespace |
| `1.01.elastic-storage.yaml` | PVs/PVCs for `es-1` (worker-1) and `es-2` (worker-2) |
| `1.02.elasticsearch.yaml` | ConfigMap (`elasticsearch.yml`, incl. `s3.client.default` endpoint/region/path-style), two `Deployment`s (es-1/es-2), Service + headless Service, `hostAliases` `rustfs → 172.20.0.3`, keystore volume |
| `1.03.es-s3-credentials.yaml` | `es-s3-credentials` (plain reference copy) + `es-s3-keystore` (pre-seeded keystore with `s3.client.default.access_key`/`secret_key`) |

> **Why a keystore?** ES 8.13's repository-s3 does **not** read
> `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars (its fallback chain is
> the EC2 instance-metadata provider only). Credentials must be placed in the
> ES keystore, which is mounted read-only into both pods.

### Layer 2 — Kibana (`kubectl apply -f "k8s/2.*"`)

| File | Contents |
|---|---|
| `2.01.kibana.yaml` | Kibana `Deployment` + Service (`basePath: /kibana`, routed by Traefik) |

### Layer 3 — FluentBit (`kubectl apply -f "k8s/3.*"`)

| File | Contents |
|---|---|
| `3.01.fluent-bit-config.yaml` | FluentBit config: CRI parser, tail of `/var/log/containers/*.log`, `[OUTPUT] kafka` → `logs-prod-nonpci-fluentbit`, `timestamp → @timestamp` |
| `3.02.fluent-bit-daemonset.yaml` | DaemonSet with `hostAliases` `broker → 172.20.0.2` |
| `3.03.fluent-bit-service.yaml` | Metrics service |

### Layer 4 — Traefik (`kubectl apply -f "k8s/4.*"`)

| File | Contents |
|---|---|
| `4.01.traefik-crds.yaml` | Traefik CRDs (IngressRoute, Middleware, …) |
| `4.02.traefik-rbac.yaml` | RBAC for the `ingress-traefik1` namespace |
| `4.03.traefik-deploy.yaml` | Traefik Deployment/Service (`web:8000`, `websecure:8443`, `traefik:8080`, `metrics:9100`) |
| `4.04.traefik-ingressroutes.yaml` | `strip-elasticsearch` middleware + `elastic-ingress` IngressRoute (`/kibana` → `kibana:5601`, `/elasticsearch` → `elasticsearch:9200`) |

> **Quoted globs required.** Shell-expanded globs are rejected by kubectl
> (`error: Unexpected args`). Always quote the pattern so kubectl expands it:
> `kubectl apply -f "k8s/1.*"`. The Makefile target `make apply-k8s-layer LAYER=n`
> already does this.

---

## Deployment Instructions

### Prerequisites

1. Install Docker, Docker Compose and vCluster
2. Set up vcluster (see vcluster.yml)
3. Ensure proper host networking

### 1. Initialize Kubernetes Cluster

---

## Basic Installation/HOST Preperation

1. Install vCluster

```bash
brew install vcluster

# Upgrade vCluster CLI to the latest version
vcluster upgrade --version v0.36.1

# Set Docker as the default driver
vcluster use driver docker

# Start vCluster Platform (optional but recommended)
vcluster platform start
```

### Creating up Multi Node K8S Cluster on vCluster

- See BUILD.md

```bash
# Deploy vcluster Kubernetes cluster
make k8s
```

### 2. Deploy Docker Compose Infrastructure

```bash
# Start all Docker services including Kafka, Syslog-ng, RustFS
make run
```

### 3. Deploy Kubernetes Elastic Stack

```bash
# Deploy Elasticsearch, Kibana, and Kafka Connect to vcluster
kubectl apply -f k8s/
```

### 4. Configure Log Feeds

Deploy various feed components:

*All Markdown based instructions are in Deployment/*

- Install and configure syslog-ng (DEPLOY_NG_FEED.md)
- Deploy Filebeat components (DEPLOY_FILEBEAT.md)
- Configure OS-level syslog collection (DEPLOY_SYSLOG.md)

---

## Key Features

### 1. Namespace Standardization

All Elastic components deployed in the **elastic** namespace for consistent management:

### 2. Multi-Collector Support

- Filebeat for container logs
- Syslog for traditional log collection  
- Syslog-ng for enhanced parsing and filtering
- FluentBit for Kubernetes-native logging

### 3. OS-level Collection

- Direct-on-OS Syslog collector for system logs
- Direct-on-OS Filebeat collector for application logs
- Both integrated with the same Kafka stack for unified processing

### 4. Scalability

- Elasticsearch: 3+ node cluster with proper disk storage
- Kibana: 2+ replica deployment
- Filebeat: DaemonSet for full node coverage

### 5. Storage Integration

- Local storage for active logs
- S3 tiered storage via RustFS for long-term retention
- Configurable retention policies (3+ months minimum)

### 6. Security

- Elasticsearch security with authentication
- Network policies for internal communication
- TLS support for transmission security

---

## Usage

1. **Log Collection**: All components automatically begin collecting logs
2. **Dashboard Access**: Access Kibana UI via port 5601
3. **Data Analysis**: Create visualizations in Kibana 
4. **Monitoring**: Use built-in logs to track system health

---

## macOS Setup Scripts

Our Lab is currently hosted on a Apple MAC, as such we'll be deploying filebeat locally and integrating with the native syslog service.

We provide automated scripts to configure macOS syslog and Filebeat to send logs to our Docker Compose infrastructure:

### Syslog Setup

```bash
./scripts/setup_macos_syslog.sh
```

This script configures macOS syslog to forward logs to Docker Compose syslog-ng at **localhost:514**.

### Filebeat Setup  

```bash
./scripts/setup_macos_filebeat.sh
```

This script configures macOS Filebeat to forward logs to Docker Compose Kafka at **localhost:9092**.

Both scripts require Mac admin privileges to execute and will:

- Install necessary components (if missing)
- Configure logging to forward to Docker Compose services
- Start the required services

---

## Docker Compose Filebeat

We also provide a Filebeat service within the Docker Compose stack that can collect logs from the host system and forward them to Kafka:

```yaml
filebeat:
  image: docker.elastic.co/beats/filebeat:8.14.0
  container_name: filebeat
  hostname: filebeat
  command: filebeat -e -c /etc/filebeat/filebeat.yml
  volumes:
    - ./conf/filebeat.yml:/etc/filebeat/filebeat.yml
    - /var/log:/var/log
    - /var/lib/docker/containers:/var/lib/docker/containers
  depends_on:
    - broker
  networks:
    - elastic
```

The Filebeat service in Docker Compose will:

- Collect logs from `/var/log` and Docker container logs
- Forward logs to the Kafka broker at `broker:29092`
- Use the topic `logs-prod-nonpci-filebeat`

For detailed configuration and setup instructions, see [DEPLOY_FILEBEAT_DOCKER.md](DEPLOY_FILEBEAT_DOCKER.md).

---

## Security Considerations

- All services use secure communication channels
- Authentication enabled for Elastic components
- RBAC policies to limit access
- Network policies to restrict inter-service communication

## S3 Storage Configuration

The system organizes snapshot data by security-classification **AWS account**:
the S3 bucket name maps 1:1 to the source AWS account name (a "set of
information/systems aligned and managed together" financially / governance
wise) and the Elasticsearch snapshot repository shares the **same name** as the
bucket. The account template holds eight classifications (`prod-pci`,
`prod-nonpci`, `prod-unregulated`, `prod-ife`, `nonprod-pci`, `nonprod-nonpci`,
`nonprod-unregulated`, `nonprod-ife`); log feeds carry the account in the topic
name (`logs-prod-nonpci-*` = simulated `prod-nonpci` account). See
`scripts/configure_s3_snapshots.sh` and `Deployment/DATASETS.md`.

Directory structure (inside each bucket; `<project name>` is the FIRST path
element, date segments are zero-padded — `year=yyyy`, `month=mm`, `day=dd`):

```
<S3 endpoint>/<bucket == aws account name>/<project name = log_analytics>/year=yyyy/month=mm/day=dd/<instanceId or Hostname>
```

Configuration parameters:

- `S3_ENDPOINT`: The S3 endpoint URL
- `S3_PROJECT_NAME`: Project identifier — first path element (default: log_analytics)
- `S3_AWS_ACCOUNT_NAME`: Default AWS account identifier — account names map
  to bucket names (default: elastic-account)
- `S3_BUCKET_NAME`: S3 bucket name (default: my-log-bucket)
- `S3_REGION`: AWS region (default: af-south-1)

All S3 credentials are stored in environment variables and should be managed
securely (the ES side uses a pre-seeded keystore — see
`k8s/1.03.es-s3-credentials.yaml`). The actual storage folder structure is
implemented by the RustFS service according to the defined naming convention.

---

## Maintenance

### Updates

Regular update of base images and configurations through configured automation.

### Monitoring

- Elasticsearch cluster health metrics
- Kibana accessibility 
- Log forwarding success rates
- Storage utilization monitoring

### Scaling

All components support horizontal scaling as per their architectural design.

---

## Contributing

This repository provides a complete, production-ready deployment solution. For enhancements or bug fixes:

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Submit a pull request

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support or questions, please refer to:

- `DEPLOY_ELASTIC.md`: Complete Kubernetes/Docker deployment documentation
- `DEPLOY_*.md`: Detailed component deployment instructions
- Existing comments in all configuration files

---

## Misc useful commands

Should you need to restart you host environment.

The following is the commands I executed to bring my cluster/s back up after having restarted Docker

- `vcluster use driver docker`

- `vcluster platform start`

- `vcluster resume my-vc1`

or

`docker restart $(docker ps -q --filter "name=my-vc1")`


You can of course also stop/pause a running cluster:

- `vcluster pause my-vc1`

To apply changes to a previously created cluster.

- `vcluster create --upgrade <cluster-name> -f vcluster.yml`

Tear Down
  
- `vcluster delete <cluster-name>`

---

## Project Pages

- [VIND](https://github.com/loft-sh/vind)

- [vCluster](https://github.com/loft-sh/vcluster)

- [Full Quickstart Guide](https://www.vcluster.com/docs/vcluster/#deploy-vcluster)

- [Slack Seerver](https://slack.loft.sh/)

**THE END**

And like that we’re done with our little trip down another Rabbit Hole, Till next time.

Thanks for following. 

### The Rabbit Hole

<img src="blog-doc/diagrams/rabbithole.jpg" alt="Our Build" width="450" height="350">

---

## ABOUT ME

I’m a techie, a technologist, always curious, love data, have for as long as I can remember always worked with data in one form or the other, Database admin, Database product lead, data platforms architect, infrastructure architect hosting databases, backing it up, optimizing performance, accessing it. Data data data… it makes the world go round.
In recent years, pivoted into a more generic Technology Architect role, capable of full stack architecture.

### By: George Leonard

- georgelza@gmail.com
- https://www.linkedin.com/in/george-leonard-945b502/
- https://medium.com/@georgelza


<img src="blog-doc/diagrams/TechCentralFeb2020-george-leonard.jpg" alt="Me" width="400" height="400">

