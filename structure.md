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
├── conf/
│   ├── filebeat.yml                    # Filebeat configuration
│   └── syslog-ng.conf                  # Syslog-ng configuration
|
├── data/
│   ├── elasticsearch                   # Elasticsearch persistent data
│   └── rustfs                          # RustFS persistent data
|
├── Deployment/
│   ├── BUILD.md                        # Build documentation
│   ├── DEPLOY_SYSLOG.md                # Syslog deployment guide
│   ├── FLUENTBIT_SELECTIVE_INGEST.md   # FluentBit filtering guide
│   ├── DEPLOY_FILEBEAT.md              # Filebeat deployment guide
│   ├── DEPLOY_ELASTIC.md               # Elastic Stack deployment guide
│   ├── DEPLOY_FILEBEAT_DOCKER.md       # Filebeat Docker Compose deployment guide
│   └── DEPLOY_NG_FEED.md               # Syslog-ng deployment guide
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
|   |
│   ├── .env                            # Infrastructure environment variables
│   ├── Makefile                        # Infrastructure deployment automation / Download base container images
│   └── README.md                       # Infrastructure documentation
|
├── k8s/
│   ├── elastic-namespace.yaml
│   ├── elasticsearch-config.yaml
│   ├── elasticsearch-pv.yaml
│   ├── elasticsearch-pvc.yaml
│   ├── elasticsearch-statefulset.yaml
│   ├── elasticsearch-service.yaml
│   ├── elasticsearch-headless-service.yaml
│   ├── fluent-bit-config.yaml
│   ├── fluent-bit-daemonset.yaml
│   ├── fluent-bit-service.yaml
│   ├── kibana-config.yaml
│   ├── kibana-deployment.yaml
│   ├── kibana-service.yaml
│   └── README.md                       # Kubernetes deployment instructions
|
├── scripts/
│   ├── setup_macos_syslog.sh           # macOS Syslog setup script
│   └── setup_macos_filebeat.sh         # macOS Filebeat setup script
|
├── .env                                # Environment variables
├── .gitignore                          # Files/directories not to GIT sync
├── docker-compose.yml                  # Docker Compose stack definition
├── Makefile                            # Deployment automation commands
├── opencode.json                       # Opencode configuration
├── README.md                           # Main README with complete deployment instructions
├── structure.md                        # This file
└── vcluster.yml                        # vCluster configuration for multi-node Kubernetes
```