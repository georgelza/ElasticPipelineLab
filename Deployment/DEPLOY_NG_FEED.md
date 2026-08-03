# Syslog-ng Installation and Configuration

## Overview

This document provides step-by-step instructions for installing and configuring Syslog-ng for log collection in the Elastic stack deployment. Syslog-ng serves as a high-performance syslog server and forwarder.

## Prerequisites

- Kubernetes cluster with appropriate permissions
- Elastic namespace already created
- Elasticsearch and Kafka services deployed
- Access to Kubernetes API for DaemonSet deployment

## Installation Steps

### 1. Create Syslog-ng DaemonSet

**File: `syslog-ng-daemonset.yaml`**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: syslog-ng
  namespace: elastic
  labels:
    app: syslog-ng
spec:
  selector:
    matchLabels:
      app: syslog-ng
  template:
    metadata:
      labels:
        app: syslog-ng
    spec:
      containers:
      - name: syslog-ng
        image: linuxserver/syslog-ng
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        ports:
        - containerPort: 514
          name: syslog
        - containerPort: 514
          name: syslog-tcp
          protocol: TCP
        volumeMounts:
        - name: syslog-ng-config
          mountPath: /etc/syslog-ng/syslog-ng.conf
          subPath: syslog-ng.conf
        - name: var-log
          mountPath: /var/log
          readOnly: true
        - name: logs
          mountPath: /var/log/syslog-ng  
      volumes:
      - name: syslog-ng-config
        configMap:
          name: syslog-ng-config
      - name: var-log
        hostPath:
          path: /var/log
      - name: logs
        hostPath:
          path: /var/log/syslog-ng
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: syslog-ng-config
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
    
    # Syslog input
    source s_syslog {
        system();
        internal();
    };
    
    # Kafka output (for integration with Elastic stack)
    destination d_kafka {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-topic")
            key("syslog")
        );
    };
    
    # Log path for Kafka (main forwarding)
    log {
        source(s_syslog);
        destination(d_kafka);
    };
```

### 2. Apply Syslog-ng Configuration

Deploy the syslog-ng daemonset:

```bash
kubectl apply -f syslog-ng-daemonset.yaml
```

### 3. Verify Installation

Check that Syslog-ng pods are running:

```bash
# Check pods
kubectl get pods -n elastic -l app=syslog-ng

# Check logs
kubectl logs -n elastic -l app=syslog-ng

# Verify that the daemonset is running on all nodes
kubectl get daemonset -n elastic syslog-ng
```

## Configuration Details

### 1. Basic Syslog-ng Configuration

**File: `syslog-ng-basic-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: syslog-ng-config
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
    
    # Syslog input
    source s_syslog {
        system();
        internal();
    };
    
    # Kafka output (used for Elastic stack integration)
    destination d_kafka {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-topic")
            key("syslog")
        );
    };
    
    # Log path for Kafka (main forwarding)
    log {
        source(s_syslog);
        destination(d_kafka);
    };
```

### 2. Advanced Syslog-ng Configuration with Filtering and Routing

**File: `syslog-ng-advanced-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: syslog-ng-advanced-config
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
    
    # Filter definitions
    filter f_auth {
        match("auth" value("program"));
    };
    
    filter f_syslog {
        match("syslog" value("program"));
    };
    
    filter f_critical {
        level("error") or level("critical");
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
    
    destination d_critical {
        kafka(
            bootstrap_servers("connect:8083")
            topic("syslog-critical")
            key("critical")
        );
    };
    
    # Route logs based on criteria
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
    
    log {
        source(s_system);
        source(s_messages);
        filter(f_critical);
        destination(d_critical);
    };
```

## Usage Instructions

### 1. Configure Syslog-ng Clients

To send logs from other systems to this Syslog-ng server:

```bash
# Example syslog-ng client configuration
# /etc/syslog-ng/conf.d/client.conf
destination d_remote {
    tcp("syslog-ng-server.elastic.svc.cluster.local" port(514));
};

log {
    source(s_syslog);
    destination(d_remote);
};
```

### 2. Direct Log Testing

Test syslog-ng sending locally:

```bash
# Send test message
logger -n syslog-ng-server.elastic.svc.cluster.local -p local0.info "Test syslog-ng message"
```

### 3. Monitor Logs

Monitor logs being processed by syslog-ng:

```bash
# Monitor logs in the pod
kubectl logs -n elastic -l app=syslog-ng -f

# Verify forwarding to Kafka
kubectl exec -it -n elastic <connect-pod> -- kafka-topics.sh --bootstrap-server broker:29092 --describe --topic syslog-topic
```

## Security Considerations

1. **Access Control**: Restrict access to the syslog-ng service through network policies
2. **Transport Security**: Enable TLS if logs pass over untrusted networks
3. **Authentication**: Set up appropriate authentication mechanisms
4. **Network Policies**: Implement Kubernetes network policies to limit inter-pod communication

## Troubleshooting

### Issue: Syslog-ng daemon not starting

Solution: Check pod logs and container configuration:

```bash
kubectl logs -n elastic -l app=syslog-ng
kubectl describe pod -n elastic -l app=syslog-ng
```

### Issue: Syslog-ng messages not being forwarded to Kafka

Solution: Verify Kafka connectivity and topic existence:

```bash
# Check if Kafka is reachable
kubectl exec -it -n elastic <kafka-pod> -- nc -z connect 8083

# List Kafka topics
kubectl exec -it -n elastic <connect-pod> -- kafka-topics.sh --bootstrap-server broker:29092 --list
```

### Issue: File access permissions

Solution: Ensure proper volume mounts and file permissions:

```bash
kubectl exec -it -n elastic <syslog-ng-pod> -- ls -la /var/log
```

## Performance Considerations

1. **Resource Limits**: Set appropriate CPU and memory limits for syslog-ng pods
2. **Log Parsing**: Optimize parsing performance for large volumes
3. **Buffering**: Configure adequate buffering for high-volume environments
4. **Compression**: Enable compression if needed for network efficiency

## Maintenance

1. **Updates**: Regularly update the base image to latest versions
2. **Log Rotation**: Configure log rotation to prevent disk exhaustion
3. **Monitoring**: Set up monitoring for log volume, errors and connectivity
4. **Backup**: Backup configuration files regularly

## Cleanup

To remove the Syslog-ng installation:

```bash
kubectl delete -f syslog-ng-daemonset.yaml
kubectl delete configmap syslog-ng-config -n elastic
```

## Integration with Elastic Stack

The configured Syslog-ng daemonSet is designed to:

1. **Collect logs** from system sources using the `system()` source
2. **Forward logs** to Kafka using the `kafka()` destination 
3. **Route through Kafka Connect** to Elasticsearch for indexing
4. **Integrate seamlessly** with the existing Elastic stack architecture

This setup ensures that all system logs are properly collected, standardized, and made available for analysis through Kibana.

## Deployment Verification

To verify correct deployment:

```bash
# Check cluster health
kubectl get pods -n elastic
kubectl get daemonset -n elastic syslog-ng

# Test log forwarding
kubectl exec -it -n elastic <syslog-ng-pod> -- logger "Test message"

# Check forwarding output
kubectl logs -n elastic -l app=syslog-ng | grep -i "forward.*topic"
```

This configuration provides a high-performance, enterprise-grade syslog-ng implementation that integrates smoothly with the Kubernetes container orchestration and Elastic stack monitoring solution.# Syslog Configuration for Kubernetes Elastic Stack  

This approach provides the most straightforward way to implement the syslog-ng source feed by using the existing manifest in the elastic directory.

## Overview

The syslog-ng daemonset in this repository provides a production-ready approach to collecting logs from Kubernetes nodes and forwarding them to the Kafka stack for processing by the Elastic stack. This implementation:

1. **Uses a standard `${REPO_NAME}/syslog-ng:latest` image** 
2. **Forwards logs to Kafka at `connect:8083`** which is exposed in your Docker Compose setup
3. **Complies with all standard practices** for Kubernetes deployments
4. **Uses the "elastic" namespace** as requested for all components
5. **Guards resource usage** with proper requests and limits

## Deployment Instructions

### 1. Add the Syslog-ng Agent (already included)

The syslog-ng daemonset manifest is located at:

`/Users/george/Desktop/Elastic/elastic/syslog-ng-daemonset.yaml`

### 2. Deploy the Component

```bash
# From the elastic directory
kubectl apply -f syslog-ng-daemonset.yaml
```

### 3. Verify Successful Deployment

```bash
# Check pods are running across nodes
kubectl get pods -n elastic -l app=syslog-ng

# Check that the daemonset is properly deployed
kubectl get daemonset -n elastic syslog-ng

# View logs to verify operation
kubectl logs -n elastic -l app=syslog-ng -f
```

## Client Configuration

To configure external systems to forward logs to this syslog-ng collector:

1. **Configure your syslog-ng clients** to send logs to the syslog-ng service endpoint:
   ```
   destination d_remote {
       tcp("syslog-ng.elastic.svc.cluster.local" port(514));
   };
   
   log {
       source(s_syslog);
       destination(d_remote);
   };
   ```

2. **Alternatively, Use Static Forwarding**:
   If you're using a more basic syslog setup:
   ```
   *.* @syslog-ng.elastic.svc.cluster.local:514
   ```

Or with rsyslog:
   ```
   *.* @syslog-ng.elastic.svc.cluster.local:514
   ```

## Network Accessibility Considerations

The current implementation requires that:

1. The Kubernetes cluster can resolve `connect:8083` 
2. Network policies allow connection from the syslog-ng pods to the Docker Compose Kafka using the `connect` name

## Troubleshooting

### Issue: Syslog-ng not starting/forwarding

1. **Check pod status**:
   ```bash
   kubectl get pods -n elastic -l app=syslog-ng
   ```

2. **Check pod logs for errors**:
   ```bash
   kubectl logs -n elastic -l app=syslog-ng -c syslog-ng
   ```

3. **Verify Kafka connectivity** (from within the pod):
   ```bash
   kubectl exec -it -n elastic <syslog-ng-pod> -- nc -z connect 8083
   ```

### Issue: No log forwarding to Kafka

1. **Verify the Kafka topic exists**:
   ```bash
   kubectl exec -it -n elastic <connect-pod> -- kafka-topics.sh --bootstrap-server broker:29092 --list
   ```

2. **Check connect logs** for failures:
   ```bash
   kubectl logs -n elastic -l app=connect
   ```

## Resource Profile

The syslog-ng daemonset is configured with:
- CPU: 100m (request), 200m (limit)
- Memory: 128Mi (request), 256Mi (limit)

These settings are optimized for low resource consumption while providing enough capacity for normal logging operations.

## Security

The syslog-ng component will create a service in the elastic namespace that allows communication from any pod in the cluster (since it's a daemon set) to the service itself. 

Ensure network policies are applied if your cluster restricts inter-pod communication.

## Integration with Monitoring Stack

Once running, logs from the syslog-ng daemonset framework will be visible in:
- Kafka subjects (topic `syslog-topic`)
- Elasticsearch indices (for index pattern creation)
- Kibana UI for visualization