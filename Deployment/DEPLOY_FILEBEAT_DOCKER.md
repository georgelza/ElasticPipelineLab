# Complete Deployment Guide - FileBeat Docker Compose Service

This document describes how to configure the Docker Compose Filebeat service to collect logs from other Docker Compose services and publish them to the Kafka broker.

## Prerequisites

1. Docker and Docker Compose installed on the system
2. Running Docker Compose stack with Kafka broker and Filebeat service
3. Access to the Docker Compose environment and containers

## Filebeat Configuration Details

The Filebeat configuration file in `data/filebeat/config/filebeat.yml` is structured to collect logs from multiple sources:

### Input Configuration

```yaml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log
    - /var/lib/docker/containers/*.log
  fields:
    source: docker-compose-filebeat
```

The configuration includes two log sources:
1. **System Logs** - Collects regular log files from `/var/log/*.log`
2. **Docker Container Logs** - Gathers JSON-formatted logs from containers via `/var/lib/docker/containers/*.log`

### Output Configuration  

```yaml
output.kafka:
  hosts: ["broker:29092"]
  topic: "logs-prod-nonpci-filebeat"
  partition.key: "log_type"
  required_acks: 1
  compression: gzip
  max_message_bytes: 1000000
```

This configuration ensures that:

- Logs are sent to the Kafka broker running at `broker:29092` 
- Logs are published to the `logs-prod-nonpci-filebeat` topic
- Gzip compression is applied for efficient transmission
- Messages don't exceed 1MB in size

## Docker Compose Integration

The Filebeat service definition in `docker-compose.yml` ensures proper container communication:

```yaml
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.14.0
    container_name: filebeat
    hostname: filebeat
    user: root
    command: filebeat -e -c /etc/filebeat/filebeat.yml
    volumes:
      - ./data/filebeat/config/filebeat.yml:/etc/filebeat/filebeat.yml
      - /var/log:/var/log
      - /var/lib/docker/containers:/var/lib/docker/containers
    depends_on:
      - broker
    networks:
      - elastic
    healthcheck:
      test: ["CMD-SHELL", "filebeat test config -e"]
      interval: 30s
      timeout: 10s
      retries: 3
```

The key aspects:

- **User Context**: Runs as root to access Docker log directories with proper permissions
- **Volumes**: Mount configuration file, system logs, and container log directory
- **Dependencies**: Ensures broker is running before Filebeat starts
- **Network**: Attached to the `elastic` network for Kafka connectivity
- **Health Check**: Validates Filebeat configuration and reports container health
- **Command**: Starts Filebeat with config file and enables logging

## Verification Steps

To verify the Filebeat service is working properly:

1. Check container status:
```bash
docker ps | grep filebeat
```

2. View Filebeat logs:
```bash
docker logs filebeat
```

3. Confirm log transmission to Kafka:
- Check that messages are appearing in the `logs-prod-nonpci-filebeat` topic
- Monitor Kafka consumer activity to verify log consumption

4. Ensure connectivity to broker:
```bash
docker exec filebeat ping broker
```

## Troubleshooting

### Common Issues and Solutions

1. **"Could not connect to Kafka"**:
   - Verify the Kafka broker is running (`docker-compose ps`)
   - Confirm `broker:29092` is accessible from the Filebeat container
   - Check Docker network connectivity (`docker network ls`)

2. **"Permission denied accessing log files"**:
   - Ensure Docker Compose has proper volume mappings for log directories
   - Verify that host directories exist and are readable

3. **"Filebeat configuration error"**:
   - Validate `conf/filebeat.yml` syntax with `filebeat test config`
   - Check the configuration file permissions

## Best Practices

1. **Monitoring**: Enable Filebeat monitoring to track log collection metrics
2. **Log Retention**: Configure appropriate log retention policies in Kafka
3. **Security**: Consider enabling TLS and authentication for production setups
4. **Performance**: Set appropriate buffer sizes and batch settings in the Kafka output configuration

This configuration enables seamless log collection from Docker Compose services and centralizes log forwarding to the Kafka infrastructure for processing and storage.