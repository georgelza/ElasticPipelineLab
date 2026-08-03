# Syslog-ng Installation and Configuration

## Overview

This document describes how Syslog-ng runs in this deployment to collect and
forward logs into the Elastic Stack via Kafka. **Syslog-ng runs as a Docker
Compose service** — there is no Kubernetes DaemonSet/manifest for it.

## Architecture

```
OS syslog (port 514) -> syslog-ng (Docker Compose) -> Kafka (syslog-topic) -> Kafka Connect -> Elasticsearch -> Kibana
```

## Prerequisites

- Docker Compose stack from the repo root (Kafka broker + Kafka Connect)
- `syslog-topic` Kafka topic created (see `scripts/cre_topics.sh`)

## Deployment

Syslog-ng is the `syslog-ng` service in `docker-compose.yml`:

```yaml
syslog-ng:
  image: linuxserver/syslog-ng
  container_name: syslog-ng
  hostname: syslog-ng
  ports:
    - "514:514/udp"
    - "514:514/tcp"
  volumes:
    - ./conf/syslog-ng-config:/etc/syslog-ng
  depends_on:
    - connect
  networks:
    - elastic
```

It uses the public `linuxserver/syslog-ng` image (a widely-used, maintained
syslog-ng image). The configuration is mounted from
`conf/syslog-ng-config/syslog-ng.conf`.

### Run the Stack

```bash
make build
make run
```

### Verify

```bash
docker compose -p elastic ps syslog-ng
docker compose -p elastic logs syslog-ng
```

## Syslog-ng Configuration

**File: `conf/syslog-ng-config/syslog-ng.conf`**

```conf
@version: 3.28

options {
    time-stamp(follow_system_tz(no));
    timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
    log_msg_size(65536);
    use_dns(no);
    use_fqdn(no);
};

source s_syslog {
    system();
    internal();
};

destination d_kafka {
    kafka(
        bootstrap_servers("connect:8083")
        topic("syslog-topic")
        key("syslog")
    );
};

log {
    source(s_syslog);
    destination(d_kafka);
};
```

### Advanced Configuration (Filtering and Routing)

Multiple topics can be used to route streams by classification:

```conf
@version: 3.28

options {
    time-stamp(follow_system_tz(no));
    timestamp_format("%Y-%m-%dT%H:%M:%S.%NZ");
    log_msg_size(65536);
    use_dns(no);
    use_fqdn(no);
};

source s_system {
    system();
};

source s_messages {
    file("/var/log/messages");
};

filter f_auth {
    match("auth" value("program"));
};

filter f_syslog {
    match("syslog" value("program"));
};

filter f_critical {
    level("error") or level("critical");
};

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

log {
    source(s_syslog);
    source(s_messages);
    filter(f_auth);
    destination(d_auth);
};

log {
    source(s_syslog);
    source(s_messages);
    filter(f_syslog);
    destination(d_syslog);
};

log {
    source(s_syslog);
    source(s_messages);
    filter(f_critical);
    destination(d_critical);
};
```

## Client Configuration

Send logs from other systems to the syslog-ng container at `localhost:514`:

```conf
destination d_remote {
    tcp("localhost" port(514));
};

log {
    source(s_syslog);
    destination(d_remote);
};
```

### Direct Log Testing

```bash
logger -n localhost -p local0.info "Test syslog-ng message"
```

## Monitor Logs

```bash
docker compose -p elastic logs -f syslog-ng

# Verify forwarding to Kafka topic
docker compose -p elastic exec broker kafka-topics \
    --bootstrap-server localhost:9092 --describe --topic syslog-topic
```

## Security Considerations

1. **Access Control**: Restrict access to syslog-ng port 514 via firewall/network rules
2. **Transport Security**: Enable TLS if logs pass over untrusted networks
3. **Authentication**: Configure appropriate mechanisms for untrusted senders

## Troubleshooting

### Issue: Syslog-ng not starting

```bash
docker compose -p elastic logs syslog-ng
```

### Issue: Syslog-ng messages not forwarded to Kafka

1. Verify the topic exists:
   ```bash
   docker compose -p elastic exec broker kafka-topics \
       --bootstrap-server localhost:9092 --list
   ```
2. Verify the `connect` service (Kafka Connect) is reachable on `:8083`
3. Check connect logs:
   ```bash
   docker compose -p elastic logs connect
   ```

## Cleanup

```bash
docker compose -p elastic rm -sf syslog-ng
```

## Integration with Elastic Stack

The Syslog-ng service:

1. **Collects logs** from system sources using the `system()` source
2. **Forwards logs** to Kafka using the `kafka()` destination
3. **Routes through Kafka Connect** to Elasticsearch for indexing
4. **Integrates** with the existing Elastic stack architecture

This setup ensures all system logs are collected, standardized, and made
available for analysis through Kibana.