## Project structure

Short layout of all the artefacts that make up our project/article.

```
.
├── blog-doc/
│   └── diagrams/
│       ├── vCluster.png
│       ├── rabbithole.jpg
│       ├── TheEnd.jpg
│       └── TechCentralFeb2020-george-leonard.jpg
|
├── data/
│   ├── filebeat/config/                # Filebeat Configuration File (filebeat.yml)
│   ├── rustfs/                         # RustFS persistent data (8 classification buckets)
│   ├── syslog-ng/config/               # Provisioned syslog-ng config (syslog-ng.conf)
│   └── vc1/                            # vcluster node data (n1/n2/n3)
|
├── Deployment/
│   ├── diagrams/
│   │   └── pipeline.svg
│   ├── ALERTS.md                       # Alerting / monitoring guide
│   ├── BUILD.md                        # Build documentation
│   ├── DATASETS.md                     # Datasets: 8 buckets + path convention + SLM policy
│   ├── DEPLOY_SYSLOG.md                # Syslog deployment guide
│   ├── FLUENTBIT_SELECTIVE_INGEST.md   # FluentBit filtering guide
│   ├── DEPLOY_FILEBEAT.md              # Filebeat deployment guide
│   ├── DEPLOY_FILEBEAT_DOCKER.md       # Filebeat Docker Compose deployment guide
│   ├── DEPLOY_ELASTIC.md               # Elastic Stack deployment guide
│   ├── DEPLOY_KIBANA.md                # Kibana integration / dashboards guide
│   ├── DEPLOY_NG_FEED.md               # Syslog-ng deployment guide
│   └── TRAEFIK.md                      # Traefik ingress layer guide
|
├── diagrams/
│   ├── architecture.png                # Architecture diagram
│   ├── architecture.svg                # Architecture diagram
│   ├── K8s.svg                         # Kubernetes architecture diagram
│   └── DockerCompose.svg               # Docker Compose architecture diagram
|
├── infrastructure/
│   ├── connect/
│   │   ├── Dockerfile                  # Dockerfile for infrastructure
│   │   └── Makefile                    # Infrastructure deployment automation
│   ├── syslog-ng/
│   │   └── syslog-ng.conf              # Canonical syslog-ng config (Kafka JSON output)
|   |
│   ├── .env                            # Infrastructure environment variables
│   ├── Makefile                        # Infrastructure deployment automation / Download base container images
│   └── README.md                       # Infrastructure documentation
|
├── k8s/
│   ├── 1.00.elastic-namespace.yaml     # elastic namespace
│   ├── 1.01.elastic-storage.yaml       # PVs/PVCs for both ES nodes
│   ├── 1.02.elasticsearch.yaml         # ES ConfigMap (s3 endpoint), 2 Deployments, Services, keystore mount
│   ├── 1.03.es-s3-credentials.yaml     # S3 credentials secret + pre-seeded ES keystore
│   ├── 1.04.external-services.yaml     # broker ExternalName Service → host.docker.internal:29092
│   ├── 2.01.kibana.yaml                # Kibana Deployment + Service
│   ├── 3.01.fluent-bit-config.yaml     # FluentBit ConfigMap (Kafka output → logs-prod-nonpci-fluentbit)
│   ├── 3.02.fluent-bit-daemonset.yaml  # FluentBit DaemonSet (all nodes)
│   ├── 3.03.fluent-bit-service.yaml    # FluentBit metrics service
│   ├── 4.01.traefik-crds.yaml          # Traefik CRDs (IngressRoute etc.)
│   ├── 4.02.traefik-rbac.yaml          # Traefik RBAC
│   ├── 4.03.traefik-deploy.yaml        # Traefik Deployment + Service
│   ├── 4.04.traefik-ingressroutes.yaml # IngressRoutes + middlewares
│   └── README.md                       # Kubernetes deployment instructions
|
├── scripts/
│   ├── README.md                       # Scripts overview / make-target mapping
│   ├── configure_elastic.sh            # ES ILM policy + index templates + Kibana data views
│   ├── configure_es_sink.sh            # Kafka Connect ES sink connector (topics.regex)
│   ├── configure_kibana_dashboards.sh  # Kibana dashboards for the 3 log feeds (saved objects)
│   ├── configure_s3_snapshots.sh       # 8 S3 snapshot repos + SLM policy
│   ├── cre_topics.sh                   # Create logs-prod-nonpci-* Kafka topics
│   ├── setup_macos_syslog.sh           # macOS Syslog setup script
│   ├── setup_macos_filebeat.sh         # macOS Filebeat setup script
│   └── take_snapshot.sh                # Ad-hoc ES snapshot (prod-nonpci repo)
|
├── .env                                # Environment variables
├── .gitignore                          # Files/directories not to GIT sync
├── docker-compose.yml                  # Docker Compose stack definition
├── Makefile                            # Deployment automation commands
├── opencode.json                       # Opencode configuration
├── README.md                           # Main README with complete deployment instructions
├── structure.md                        # This file
├── Todo.md                             # Deployment tracking list
├── Done.md                             # Archived history of completed work (sections 1-8)
└── vcluster.yml                        # vCluster configuration for multi-node Kubernetes
```
