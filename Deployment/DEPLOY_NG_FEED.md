# Syslog-ng Installation and Configuration

## Overview

This document describes how Syslog-ng runs in this deployment to collect and
forward logs into the Elastic Stack via Kafka. **Syslog-ng runs as a Docker
Compose service** — there is no Kubernetes DaemonSet/manifest for it.

## Architecture

```
OS syslog (port 514) -> syslog-ng (Docker Compose) -> Kafka (logs-prod-nonpci-syslog) -> Kafka Connect -> Elasticsearch -> Kibana
```

## Prerequisites

- Docker Compose stack from the repo root (Kafka broker + Kafka Connect)
- `logs-prod-nonpci-syslog` Kafka topic created (see `scripts/cre_topics.sh`)

## Deployment

Syslog-ng is the `syslog-ng` service in `docker-compose.yml`:

```yaml
syslog-ng:
  # Official syslog-ng image — includes the native Kafka module so syslog-ng
  # publishes DIRECTLY to the broker (no file/Filebeat hop).
  image: balabit/syslog-ng:latest
  container_name: syslog-ng
  hostname: syslog-ng
  ports:
    - "514:5514/udp"   # Standard Syslog UDP (host 514 -> container 5514)
    - "601:6601/tcp"   # Standard Syslog TCP (host 601 -> container 6601)
  volumes:
    - ./data/syslog-ng/config/syslog-ng.conf:/etc/syslog-ng/syslog-ng.conf:ro
  depends_on:
    - broker
  networks:
    - elastic
```

The official `balabit/syslog-ng` image ships the native librdkafka-based Kafka
module. The canonical configuration lives at
`infrastructure/syslog-ng/syslog-ng.conf` and is provisioned by `make run`
into `data/syslog-ng/config/syslog-ng.conf`.

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

**File: `infrastructure/syslog-ng/syslog-ng.conf`** (canonical source,
provisioned by `make run` into `data/syslog-ng/config/syslog-ng.conf`):

```conf
@version: 4.2
@include "scl.conf"

options {
    keep-timestamp(no);
    ts-format("iso");
    frac-digits(3);
    log-msg-size(65536);
    use-dns(no);
    use-fqdn(no);
};

source s_syslog {
    internal();
    udp(ip(0.0.0.0) port(5514));
    tcp(ip(0.0.0.0) port(6601));
};

destination d_kafka {
    kafka(
        bootstrap-servers("broker:29092")
        topic("logs-prod-nonpci-syslog")
        key("syslog")
        message('$(format-json --scope rfc5424 --scope nv-pairs --pair @timestamp="${ISODATE}")')
    );
};

log {
    source(s_syslog);
    destination(d_kafka);
};
```

Payloads are JSON (`$(format-json)`) with an `@timestamp` pair so the ES sink
connector (`JsonConverter`) can index them directly. `bootstrap-servers`
MUST point at the Kafka **broker** (`broker:29092`) — not at Kafka Connect
(`connect:8083`, which is the Connect REST API).

### Advanced Configuration (Filtering and Routing)

Multiple topics can be used to route streams by classification. Topic names
must follow the `logs-<account>-<source>` convention so the sink connector's
`logs-prod-nonpci-.*` wildcard picks them up:

```conf
@version: 4.2
@include "scl.conf"

options {
    keep-timestamp(no);
    ts-format("iso");
    frac-digits(3);
    log-msg-size(65536);
    use-dns(no);
    use-fqdn(no);
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
        bootstrap-servers("broker:29092")
        topic("logs-prod-nonpci-auth")
        key("auth")
    );
};

destination d_syslog {
    kafka(
        bootstrap-servers("broker:29092")
        topic("logs-prod-nonpci-syslog")
        key("syslog-all")
    );
};

destination d_critical {
    kafka(
        bootstrap-servers("broker:29092")
        topic("logs-prod-nonpci-critical")
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

Send logs from other systems to the syslog-ng container. The container exposes
UDP 5514 and TCP 6601, published on the host as **UDP 514** and **TCP 601**
(see `docker-compose.yml`):

```conf
destination d_remote {
    udp("localhost" port(514));
    tcp("localhost" port(601));
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
    --bootstrap-server localhost:9092 --describe --topic logs-prod-nonpci-syslog
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
2. Verify the Kafka `broker` is reachable on `broker:29092` (syslog-ng
   publishes directly to the broker — Kafka Connect is only the ES sink):
   ```bash
   docker compose -p elastic exec broker nc -z broker 29092
   ```
3. Check syslog-ng logs:
   ```bash
   docker compose -p elastic logs syslog-ng
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