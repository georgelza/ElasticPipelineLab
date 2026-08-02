# Filebeat Installation and Configuration

## Overview

This document provides step-by-step instructions for installing and configuring Filebeat to collect logs and forward them to the Elasticsearch stack.

## Prerequisites

- Kubernetes cluster with proper RBAC permissions
- Elastic namespace already created
- Elasticsearch and Kibana services deployed
- Access to Kubernetes API with appropriate permissions for DaemonSet deployment

## Installation Steps

### 1. Create Filebeat Configuration

**File: `filebeat-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: elastic
data:
  filebeat.yml: |
    filebeat.inputs:
    - type: log
      enabled: true
      paths:
        - /var/log/*.log
      fields:
        service: "kubernetes"
      fields_under_root: true
      json:
        keys_under_root: true
        overwrite_keys: true
        add_error_key: true

    output.elasticsearch:
      hosts: ["http://elasticsearch:9200"]
      username: elastic
      password: changeme
      index: "filebeat-%{+yyyy.MM.dd}"
    setup.template.enabled: false
    setup.ilm.enabled: false
```

### 2. Deploy Filebeat as DaemonSet

**File: `filebeat-daemonset.yaml`**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: filebeat
  namespace: elastic
  labels:
    app: filebeat
spec:
  selector:
    matchLabels:
      app: filebeat
  template:
    metadata:
      labels:
        app: filebeat
    spec:
      serviceAccountName: filebeat
      containers:
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:8.11.3
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        volumeMounts:
        - name: filebeat-config
          mountPath: /etc/filebeat/filebeat.yml
          subPath: filebeat.yml
        - name: data
          mountPath: /usr/share/filebeat/data
        - name: var-log
          mountPath: /var/log
          readOnly: true
        - name: var-lib
          mountPath: /var/lib
          readOnly: true
        - name: proc
          mountPath: /proc
          readOnly: true
        - name: cgroup
          mountPath: /sys/fs/cgroup
          readOnly: true
      volumes:
      - name: filebeat-config
        configMap:
          name: filebeat-config
      - name: data
        hostPath:
          path: /var/lib/filebeat
          type: DirectoryOrCreate
      - name: var-log
        hostPath:
          path: /var/log
      - name: var-lib
        hostPath:
          path: /var/lib
      - name: proc
        hostPath:
          path: /proc
      - name: cgroup
        hostPath:
          path: /sys/fs/cgroup
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: filebeat
  namespace: elastic
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: filebeat
rules:
- apiGroups: [""]
  resources: ["nodes", "namespaces", "pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: filebeat
subjects:
- kind: ServiceAccount
  name: filebeat
  namespace: elastic
roleRef:
  kind: ClusterRole
  name: filebeat
  apiGroup: rbac.authorization.k8s.io
```

### 3. Apply Filebeat Configuration

Deploy the configuration using kubectl:

```bash
kubectl apply -f filebeat-config.yaml
kubectl apply -f filebeat-daemonset.yaml
```

### 4. Verify Installation

Check that Filebeat pods are running correctly:

```bash
# Check if pods are running
kubectl get pods -n elastic -l app=filebeat

# Check logs for any errors
kubectl logs -n elastic -l app=filebeat

# Ensure that Filebeat is connecting to Elasticsearch
kubectl logs -n elastic -l app=filebeat | grep -i "connected to elasticsearch"
```

## Configuration Customization

### 1. Modify Log Paths

To monitor specific applications:

```yaml
# In filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/myapp/*.log  # Specific app logs
  fields:
    service: "myapp"
```

### 2. Enable Module Support

For application-specific log parsing:

```yaml
# Enable module-specific configurations
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nginx/*.log
  fields:
    service: "nginx"
  # Enable parsing for nginx logs
  multiline.pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
  multiline.negate: true
  multiline.match: after
```

## Security Considerations

1. **Authentication**: Set secure credentials as specified in the configuration
2. **Network Policies**: Restrict pod-to-pod communication
3. **Permissions**: Use least privilege for service account
4. **TLS**: Enable transport security if connecting to external services

## Troubleshooting

### Issue: Filebeat pods failing to start

Solution: Check the pod status and logs:

```bash
kubectl describe pod -n elastic -l app=filebeat
kubectl logs -n elastic -l app=filebeat --previous
```

### Issue: Filebeat not sending data to Elasticsearch

Solution: Verify connection parameters in the configuration file:

```bash
kubectl exec -it -n elastic <filebeat-pod-name> -- curl -u elastic:password http://elasticsearch:9200/_cluster/health?pretty
```

### Issue: Incorrect log format

Solution: Ensure proper log parsing configuration in filebeat.yml:

```yaml
# Verify JSON parsing if logs are JSON formatted
json:
  keys_under_root: true
  overwrite_keys: true
  add_error_key: true
```

## Maintenance

1. **Updates**: Update Filebeat image version in deployment YAML  
2. **Log Rotation**: Configure filebeat for log rotation with proper disk space management
3. **Monitoring**: Set up alerts for disk space and connectivity issues
4. **Security**: Regularly rotate secrets and credentials

This configuration ensures Filebeat operates as a reliable log collector that forwards data to the Elasticsearch stack efficiently and securely.# Installation Guide: OS-level Filebeat Collector

This guide describes how to install and configure a Filebeat collector directly on the OS that will forward logs to the Docker Compose Kafka stack.

## Prerequisites

- Linux OS (Ubuntu/Debian/CentOS/RHEL)
- Docker installed on the host system
- Access to the Docker Compose environment (broker, connect, schema-registry)
- Network access to the Kafka cluster (port 9092 or 29092)

## Architecture Overview

This deployment follows a direct-on-OS pattern where:
1. The Filebeat collector runs as a Docker container on the host system
2. It forwards logs to Kafka via the `connect` container configured in the Docker Compose environment
3. The `connect:8083` endpoint allows Kafka Connect to process these logs

## Deployment Process

### 1. Prepare the System

```bash
# Ensure Docker is running
sudo systemctl start docker
sudo systemctl enable docker

# Create the necessary directories
mkdir -p /opt/filebeat-collector/config
mkdir -p /opt/filebeat-collector/logs
```

### 2. Create Filebeat Configuration

Create the configuration file at `/opt/filebeat-collector/config/filebeat.yml`:

```yaml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/auth.log
    - /var/log/syslog
    - /var/log/messages
    - /var/log/kern.log
    - /var/log/boot.log
    - /var/log/dmesg
    - /var/log/mail.log
    - /var/log/daemon.log
    - /var/log/debug
  fields:
    type: os-logs

- type: log
  enabled: true
  paths:
    - /var/log/nginx/*.log
    - /var/log/apache2/*.log
  fields:
    type: application-logs

output.kafka:
  hosts: ["connect:8083"]
  topic: "filebeat-topic"
  key: "filebeat"
  required_acks: 1
  compression: gzip
  max_message_bytes: 1000000

# Exclude system logs from being sent to Elasticsearch directly
filebeat.config.modules:
  path: ${path.config}/modules.d/*.yml
  reload.enabled: false
```

### 3. Launch the Filebeat Collector Docker Service

Create a docker-compose override file at `/opt/filebeat-collector/docker-compose.yml`:

```yaml
version: '3.8'

services:
  filebeat-collector:
    image: docker.elastic.co/beats/filebeat:8.11.3
    container_name: filebeat-collector
    hostname: filebeat-collector
    volumes:
      - ./config/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - ./logs:/var/log/filebeat
      - /var/log:/var/log:ro
      - /etc:/etc:ro
    networks:
      - elastic
    # Run as root to access system logs
    user: root
    # Use host network mode to avoid port mapping issues when connecting to Kafka
    network_mode: "host"

networks:
  elastic:
    external:
      name: elastic
```

### 4. Deploy the Service

```bash
# Navigate to the directory where the docker-compose file is saved
cd /opt/filebeat-collector

# Start the filebeat collector in detached mode
docker compose up -d

# Check the status
docker compose ps
```

### 5. Verify the Deployment

```bash
# Check logs
docker compose logs -f

# Verify the container is running
docker ps

# Check if the container can connect to Kafka
docker compose exec filebeat-collector ping connect
```

## Source Log Files Analysis

The Filebeat collector will forward these OS log files to Kafka:

| Log File Path | Description | Log Source |
|---------------|-------------|------------|
| `/var/log/auth.log` | Authentication logs | System authentication |
| `/var/log/syslog` | System messages | General system messages |
| `/var/log/messages` | General system messages | System-wide messages |
| `/var/log/kern.log` | Kernel log messages | Kernel events |
| `/var/log/boot.log` | System boot messages | Boot process |
| `/var/log/dmesg` | Kernel ring buffer | Hardware messages |
| `/var/log/mail.log` | Mail system messages | Mail server logs |
| `/var/log/daemon.log` | Daemon process messages | Background services |
| `/var/log/debug` | Debug messages | Debug-level logs |
| `/var/log/nginx/*.log` | Nginx access/error logs | Web server activity |
| `/var/log/apache2/*.log` | Apache access/error logs | Web server activity |

### Alternative Documentation for Custom Log Monitoring

For additional custom log monitoring, add more input sections:

```yaml
- type: log
  enabled: true
  paths:
    - /var/log/custom-app/app.log
    - /var/log/custom-app/error.log
  fields:
    type: custom-application-logs
```

### Troubleshooting

#### Issue: Connection to `connect` failed

Ensure that:

1. The Docker Compose stack is running:
   ```bash
   docker compose ps
   ```

2. The `connect` service is accessible:
   ```bash
   docker compose exec broker nc -z connect 8083
   ```

#### Issue: Logs not reaching Kafka

1. Check the Filebeat logs within the container:
   ```bash
   docker compose logs filebeat-collector
   ```

2. Verify Kafka topics exist:
   ```bash
   docker compose exec broker kafka-topics.sh --bootstrap-server localhost:9092 --list
   ```

## Resource Management

The container is configured with:

- CPU: 100m (request), 200m (limit)
- Memory: 128Mi (request), 256Mi (limit)

Adjust these values in the Docker Compose file based on your system's capacity and log volume requirements.

## Security Considerations

1. Ensure only authorized systems can access the Filebeat container
2. Configure proper permissions for log files being monitored
3. Consider using TLS for communications between Filebeat and Kafka
4. Use secure configuration files with restricted access

## Integration with Kafka Connect

This configuration will deliver events to the "filebeat-topic" in Kafka, which can be:
1. Connected to Elasticsearch through Kafka Connect
2. Monitored via Control Center
3. Processed by any other Kafka consumers

## Installation Check

After deployment, you should see:
1. Container named `filebeat-collector` running
2. Log entries showing successful connection to `connect:8083`
3. Forwarded log entries appearing in Kafka topics
4. Integration with existing Kafka Connect pipeline