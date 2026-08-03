# Installation Guide: OS-level Syslog Collector

> **Current deployment (updated):** syslog-ng now runs as a **Docker Compose
> service** (`docker-compose.yml`, image `linuxserver/syslog-ng`), not a
> Kubernetes DaemonSet. Its configuration is provisioned from the canonical
> source `infrastructure/syslog-ng/syslog-ng.conf` into
> `./data/syslog-ng/config/syslog-ng.conf` by `make run`. It publishes **JSON
> payloads** (`$(format-json)`) to the `syslog-topic` Kafka topic on
> **`broker:29092`** (the Kafka broker — **not** `connect:8083`, which is the
> Kafka Connect REST API). The Kafka → Elasticsearch sink connector then
> indexes `syslog-topic` into the `logs-syslog` ES index. The Kubernetes
> DaemonSet/ConfigMap sections further down are kept for reference but are
> **deprecated** for this repo.

## Prerequisites

- Linux OS (Ubuntu/Debian/CentOS/RHEL)
- Docker installed on the host system
- Access to the Docker Compose environment (broker, connect, schema-registry)
- Network access to the Kafka cluster (port 9092 or 29092)

## Architecture Overview

This deployment follows a direct-on-OS pattern where:

1. The syslog collector (syslog-ng) runs as a Docker Compose service on the host system
2. It forwards logs directly to the Kafka broker (`broker:29092`) — NOT via Kafka Connect
3. Kafka Connect (`connect:8083`) only runs the **Elasticsearch sink connector** that consumes the topic and indexes into Elasticsearch

## Deployment Process

### 1. Prepare the System

```bash
# Ensure Docker is running
sudo systemctl start docker
sudo systemctl enable docker

# Create the necessary directories
mkdir -p /opt/syslog-collector/config
mkdir -p /opt/syslog-collector/logs
```

### 2. Create Syslog Collector Configuration

The canonical configuration lives at `infrastructure/syslog-ng/syslog-ng.conf`
and is provisioned by `make run` into `./data/syslog-ng/config/syslog-ng.conf`
(the LinuxServer image mounts that directory at `/config`). Equivalent
standalone configuration:

```conf
@version: 4.2

# Global options
options {
    time-stamp(follow_system_tz(no));
    timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
    log_msg_size(65536);
    use_dns(no);
    use_fqdn(no);
};

# Syslog input sources
source s_syslog {
    system();
    internal();
};

# File input for specific OS log files
source s_files {
    file("/var/log/auth.log" flags(no-parse) program_override("auth"));
    file("/var/log/syslog" flags(no-parse) program_override("syslog"));
    file("/var/log/messages" flags(no-parse) program_override("messages"));
    file("/var/log/kern.log" flags(no-parse) program_override("kernel"));
    file("/var/log/boot.log" flags(no-parse) program_override("boot"));
    file("/var/log/dmesg" flags(no-parse) program_override("dmesg"));
};

# Kafka output destination — bootstrap_servers points at the KAFKA BROKER
# (broker:29092). connect:8083 is Kafka Connect's REST API, NOT a broker.
destination d_kafka {
    kafka(
        bootstrap_servers("broker:29092")
        topic("syslog-topic")
        key("syslog")
        # JSON payload so the ES sink JsonConverter can index it directly
        value("$(format-json --scope rfc5424 --scope nv-pairs)\n")
        config(compression.type("snappy"))
    );
};

# Log path for Kafka
log {
    source(s_syslog);
    destination(d_kafka);
};

# Log path for file inputs
log {
    source(s_files);
    destination(d_kafka);
};
```

### 3. Launch the Syslog Collector Docker Service

In this repo the syslog-ng service is already defined in the root
`docker-compose.yml` — just run `make run` (which provisions the config and
starts the stack). A standalone override for another host would look like:

```yaml
version: '3.8'

services:
  syslog-ng:
    image: linuxserver/syslog-ng
    container_name: syslog-ng
    hostname: syslog-ng
    ports:
      - "514:5514/udp"   # Standard Syslog UDP
      - "601:6601/tcp"   # Standard Syslog TCP
    environment:
      - PUID=1000        # Match your local user ID to avoid permission issues
      - PGID=1000        # Match your local group ID
      - TZ=Etc/UTC       # Set your desired timezone
    volumes:
      - ./conf/syslog-ng-config:/config       # Location for your custom syslog-ng.conf
      - ./data/syslog-ng/logs:/var/log/syslog # Destination folder where logs will accumulate
    depends_on:
      # syslog-ng publishes straight to the Kafka broker, so only broker is needed
      - broker
    networks:
      - elastic

networks:
  elastic:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### 4. Deploy the Service

```bash
# Navigate to the directory where the docker-compose file is saved
cd /opt/syslog-collector

# Start the syslog collector in detached mode
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
docker compose exec syslog-collector ping connect
```

## Source Log Files Analysis

The syslog collector will forward these OS log files to Kafka:

| Log File Path | Description | Log Source |
|:--- |:--- |:--- |
| `/var/log/auth.log` | Authentication logs | System authentication |
| `/var/log/syslog` | System messages | General system messages |
| `/var/log/messages` | General system messages | System-wide messages |
| `/var/log/kern.log` | Kernel log messages | Kernel events |
| `/var/log/boot.log` | System boot messages | Boot process |
| `/var/log/dmesg` | Kernel ring buffer | Hardware messages |
| `/var/log/mail.log` | Mail system messages | Mail server logs |
| `/var/log/daemon.log` | Daemon process messages | Background services |
| `/var/log/debug` | Debug messages | Debug-level logs |

### Alternative Documentation for Static File Monitoring

For monitoring additional log file types, modify the configuration as follows:

```conf
# Example of additional file monitoring
source s_custom_files {
    file("/var/log/nginx/access.log" flags(no-parse) program_override("nginx"));
    file("/var/log/nginx/error.log" flags(no-parse) program_override("nginx"));
    file("/var/log/apache2/access.log" flags(no-parse) program_override("apache2"));
    file("/var/log/apache2/error.log" flags(no-parse) program_override("apache2"));
};
```

### Troubleshooting

#### Issue: Connection to Kafka (`broker:29092`) failed

Ensure that:

1. The Docker Compose stack is running:
   ```bash
   docker compose ps
   ```

2. The `broker` service is accessible:
   ```bash
   docker compose exec broker nc -z broker 29092
   ```

#### Issue: Logs not reaching Kafka

1. Check the syslog-ng logs within the container:
   ```bash
   docker compose logs syslog-collector
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

1. Ensure only authorized systems can connect to port 514 (UDP/TCP) 
2. Validate log file permissions 
3. Consider adding TLS security for communications between collector and Kafka
4. Use proper network segmentation if the host is exposed to the internet

## Integration with Kafka Connect

This configuration will deliver events to the "syslog-topic" in Kafka, which can be:

1. Connected to Elasticsearch through Kafka Connect
2. Monitored via Control Center
3. Processed by any other Kafka consumers

## Installation Check

After deployment, you should see:

1. Container named `syslog-ng` running
2. Log entries showing successful connection to `broker:29092`
3. Forwarded log entries appearing in the `syslog-topic` Kafka topic
4. The `elasticsearch-sink` connector indexing `syslog-topic` into the `logs-syslog` ES index
5. Documents visible in the `logs-syslog*` Kibana data view

---

# Syslog Installation and Configuration (DEPRECATED — K8s DaemonSet approach)

> **Deprecated:** the following Kubernetes DaemonSet/ConfigMap based syslog
> deployment is **not used** in this repo. syslog-ng runs as a Docker Compose
> service (see above). This section is kept only for historical reference and
> contains outdated `connect:8083` broker references.

## Overview

This document provides step-by-step instructions for installing and configuring Syslog for log collection in the Elastic stack deployment.

## Prerequisites

- Kubernetes cluster with appropriate permissions
- Elastic namespace already created
- Elasticsearch and Kafka services deployed
- Access to Kubernetes API for DaemonSet deployment

## Installation Steps

### 1. Create Syslog DaemonSet

**File: `syslog-daemonset.yaml`**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: syslog
  namespace: elastic
  labels:
    app: syslog
spec:
  selector:
    matchLabels:
      app: syslog
  template:
    metadata:
      labels:
        app: syslog
    spec:
      containers:
      - name: syslog
        image: busybox:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          # Install syslog daemon
          apk add --no-cache syslog-ng
          
          # Create configuration file
          cat > /etc/syslog-ng/syslog-ng.conf << 'EOF'
          @version: 3.28
          
          # Global options
          options {
              time-stamp(follow_system_tz(no));
              timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
              log_msg_size(65536);
          };
          
          # Syslog input
          source s_syslog {
              system();
              internal();
          };
          
          # Kafka output
          destination d_kafka {
              kafka(
                  bootstrap_servers("connect:8083")
                  topic("syslog-topic")
                  key("syslog")
              );
          };
          
          # Log path
          log {
              source(s_syslog);
              destination(d_kafka);
          };
          EOF
          
          # Start syslog-ng
          syslog-ng --no-daemon --config-file=/etc/syslog-ng/syslog-ng.conf
        ports:
        - containerPort: 514
          name: syslog
        volumeMounts:
        - name: syslog-config
          mountPath: /etc/syslog-ng
        - name: var-log
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: syslog-config
        emptyDir: {}
      - name: var-log
        hostPath:
          path: /var/log
---
apiVersion: v1
kind: Service
metadata:
  name: syslog
  namespace: elastic
  labels:
    app: syslog
spec:
  ports:
  - port: 514
    name: syslog
  selector:
    app: syslog
```

### 2. Apply Syslog Configuration

Deploy the syslog daemonset:

```bash
kubectl apply -f syslog-daemonset.yaml
```

### 3. Verify Installation

Check that Syslog pods are running:

```bash
# Check pods
kubectl get pods -n elastic -l app=syslog

# Check logs
kubectl logs -n elastic -l app=syslog

# Verify the daemonset is running on all nodes
kubectl get daemonset -n elastic syslog
```

## Configuration Details

### 1. Basic Syslog Configuration

**File: `syslog-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: syslog-config
  namespace: elastic
data:
  syslog-ng.conf: |
    @version: 3.28
    
    # Global options
    options {
        time-stamp(follow_system_tz(no));
        timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
        log_msg_size(65536);
    };
    
    # Syslog input
    source s_syslog {
        system();
        internal();
    };
    
    # Kafka output
    destination d_kafka {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-topic")
            key("syslog")
        );
    };
    
    # Log path
    log {
        source(s_syslog);
        destination(d_kafka);
    };
```

### 2. Advanced Syslog Configuration for Filtering

**File: `advanced-syslog-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: advanced-syslog-config
  namespace: elastic
data:
  syslog-ng.conf: |
    @version: 3.28
    
    # Global options
    options {
        time-stamp(follow_system_tz(no));
        timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
        log_msg_size(65536);
        use_dns(no);
        use_fqdn(no);
    };
    
    # Syslog sources
    source s_system {
        system();
    };
    
    source s_messages {
        file("/var/log/messages");
    };
    
    # Filtering and routing
    filter f_auth {
        match("auth" value("program"));
    };
    
    filter f_syslog {
        match("syslog" value("program"));
    };
    
    # Destinations
    destination d_auth {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-auth")
            key("auth")
        );
    };
    
    destination d_syslog {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-all")
            key("syslog-all")
        );
    };
    
    # Route logs
    log {
        source(s_system);
        source(s_messages);
        filter(f_auth);
        destination(d_auth);
    };
    
    log {
        source(s_system);
        source(s_messages);
        filter(f_syslog);
        destination(d_syslog);
    };
```

## Usage Instructions

### 1. Configure Syslog Clients

To send logs from other systems to this Syslog server:

```bash
# Example syslog client configuration (syslog-ng)
# /etc/syslog-ng/conf.d/client.conf
destination d_remote {
    tcp("syslog-server.elastic.svc.cluster.local" port(514));
};

log {
    source(s_syslog);
    destination(d_remote);
};
```

### 2. Direct Log Testing

Test syslog sending locally:

```bash
# Send test message
logger -n syslog-server.elastic.svc.cluster.local -p local0.info "Test syslog message"
```

## Security Considerations

1. **Access Control**: Restrict access to the syslog service
2. **Network Policies**: Implement network policies to limit inter-pod communication
3. **Transport Security**: Enable TLS if logs pass over untrusted networks
4. **Authentication**: Set up appropriate authentication mechanisms

## Troubleshooting

### Issue: Syslog daemon not starting

Solution: Check pod logs and container configuration:

```bash
kubectl logs -n elastic -l app=syslog
kubectl describe pod -n elastic -l app=syslog
```

### Issue: Syslog messages not being forwarded

Solution: Verify Kafka connectivity:

```bash
# Check if Kafka is reachable
kubectl exec -it -n elastic <kafka-pod> -- nc -z connect 8083

# Monitor Kafka topics
kubectl exec -it -n elastic <connect-pod> -- kafka-topics.sh --bootstrap-server broker:29092 --list
```

### Issue: File access permissions

Solution: Ensure proper volume mounts:

```bash
kubectl exec -it -n elastic <syslog-pod> -- ls -la /var/log
```

## Maintenance

1. **Updates**: Regularly update the base image
2. **Log Rotation**: Configure proper log rotation to prevent disk exhaustion
3. **Monitoring**: Set up alerts for log volume spikes or connectivity issues
4. **Backup**: Backup configuration files regularly

## Cleanup

To remove the Syslog installation:

```bash
kubectl delete -f syslog-daemonset.yaml
kubectl delete configmap syslog-config -n elastic
```

This configuration sets up a Syslog server that can collect logs from various sources and forward them to the Kafka middleware for processing by the Elasticsearch stack.