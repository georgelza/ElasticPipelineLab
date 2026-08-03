# Data Sets and Topic Management

## Configuration and Source Feeds

Topics follow the `logs-<account>-<source>` convention so the ES sink
connector can subscribe to an account's whole feed family with a single
wildcard (`logs-prod-nonpci-.*`). The account segment is the **full AWS
account name** (e.g. `prod-nonpci`) — we currently **simulate a single account
(`prod-nonpci`)** for the four lab feeds; the account template holds **eight**
classifications (see "S3 Storage Organization" below).

### Source Feed Configuration:

1. **Syslog-ng Config** (`infrastructure/syslog-ng/syslog-ng.conf`, provisioned
   to `data/syslog-ng/config/syslog-ng.conf`):

   ```
   topic("logs-prod-nonpci-syslog")
   ```

2. **Filebeat Config** (`data/filebeat/config/filebeat.yml`):

   ```
   topic: "logs-prod-nonpci-filebeat"
   ```

3. **FluentBit Config** (`k8s/3.01.fluent-bit-config.yaml`):

   ```
   topics logs-prod-nonpci-fluentbit
   ```

4. **Topic creation** (`scripts/cre_topics.sh`) — creates
   `logs-prod-nonpci-syslog`, `logs-prod-nonpci-filebeat`,
   `logs-prod-nonpci-fluentbit`, `logs-prod-nonpci-log4j`
   (2 partitions, 1 replica, 7-day retention).

### Sink Configuration:

All `logs-prod-nonpci-*` topics are consumed by a single Elasticsearch sink
connector (`scripts/configure_es_sink.sh`) that subscribes with the wildcard
`topics.regex: logs-prod-nonpci-.*` and writes each topic into a same-named ES
index:

- `logs-prod-nonpci-syslog`    → index `logs-prod-nonpci-syslog`
- `logs-prod-nonpci-filebeat`  → index `logs-prod-nonpci-filebeat`
- `logs-prod-nonpci-fluentbit` → index `logs-prod-nonpci-fluentbit`
- `logs-prod-nonpci-log4j`     → index `logs-prod-nonpci-log4j`
- future feeds of the same account (`logs-prod-nonpci-*`) are picked up
  automatically and land in the same account's ES repo / S3 bucket

## Multi-Bucket Segmentation by Security Classification

The Elastic "database" is split into multiple buckets by security
classification. The S3 bucket name maps 1:1 to the source AWS account name — a
"set of information/systems that are aligned and managed together" from a
financial/governance perspective — and the Elasticsearch snapshot repository
shares the same name.

### Security Classifications:

1. **Production vs Non-Production**
2. **PCI vs Non-PCI**
3. **IFE (Internet Facing Exposed)**
4. **Unregulated**

### Implementation Approach:

#### 1. Topic-based Segregation:

Each source feed publishes to a `logs-<account>-<source>` topic. The account
segment in the topic name is what ties a feed to its originating account (and
therefore to that account's ES repository / S3 bucket).

**Current topics (simulated single account `prod-nonpci`):**

- `logs-prod-nonpci-syslog`:    For syslog-ng forwarded logs (Docker Compose)
- `logs-prod-nonpci-filebeat`:  For Filebeat in Docker Compose
- `logs-prod-nonpci-fluentbit`: For FluentBit Kubernetes container logs
- `logs-prod-nonpci-log4j`:     For Log4j appender logs (applications)

**Planned topics:**

New sources should follow the same `logs-<account>-<source>` convention so they
are picked up by the account's sink wildcard automatically:

- `logs-prod-nonpci-network` (Network data)
- `logs-prod-nonpci-app` / `logs-prod-nonpci-dns` / ... (future sources)
- `logs-<other-account>-<source>` for feeds originating from other accounts
  (in production ~18 accounts map onto the 8 classifications below)

#### 2. Connector-based Bucket Assignment:

The Elasticsearch sink connector (`elasticsearch-sink`) ingests all feeds of an
account (`topics.regex: logs-prod-nonpci-.*`) into same-named ES indices, which
are then snapshotted into the account's ES repository / S3 bucket. When
additional accounts go live, deploy a matching sink per account wildcard:

- `elasticsearch-sink` (wildcard `logs-prod-nonpci-.*`) → `prod-nonpci`
  repo/bucket
- future: `logs-prod-pci-.*` → `prod-pci`, `logs-prod-ife-.*` → `prod-ife`,
  `logs-nonprod-pci-.*` → `nonprod-pci`, ... (one sink per account prefix)

#### 3. Implementation Steps:

1. **Configuration Changes**:

   - Modify source configurations to use account-qualified topics
   - Update Kafka source configurations to specify new topics

2. **Deployment Modifications**:

   - Deploy sink connectors per account wildcard
   - Configure Elasticsearch indices per account (snapshot routing via SLM)

3. **Topic Management**:

   - Create distinct Kafka topics per account + source
   - Implement appropriate retention policies per classification

#### 4. S3 Storage Organization:

Snapshots are offloaded to the RustFS object store (`rustfs:9000`, published on
the host at `127.0.0.1:9000`). The account template holds **eight
security-classification accounts** — the S3 bucket name maps 1:1 to the source
AWS account name and the Elasticsearch snapshot repository shares the **same
name** (`scripts/configure_s3_snapshots.sh`):

| Usage | bucket | ES repo | Topic prefix |
|:--- |:--- |:--- |:--- |
| Production – PCI | `prod-pci` | `prod-pci` | `logs-prod-pci-*` |
| Production – Non-PCI | `prod-nonpci` | `prod-nonpci` | `logs-prod-nonpci-*` |
| Production – Unregulated | `prod-unregulated` | `prod-unregulated` | `logs-prod-unregulated-*` |
| Production - IFE | `prod-ife` | `prod-ife` | `logs-prod-ife-*` |
| Non-Production – PCI | `nonprod-pci` | `nonprod-pci` | `logs-nonprod-pci-*` |
| Non-Production – Non-PCI | `nonprod-nonpci` | `nonprod-nonpci` | `logs-nonprod-nonpci-*` |
| Non-Production – Unregulated | `nonprod-unregulated` | `nonprod-unregulated` | `logs-nonprod-unregulated-*` |
| Non-Production - IFE | `nonprod-ife` | `nonprod-ife` | `logs-nonprod-ife-*` |

The directory structure follows the convention — the `<project name>` is the
**first element** of the path (for our usage: `log_analytics`), the `<aws
account name>` is the **second element** (the account is a member of the
project; the bucket itself == the account name), and the date segments are
zero-padded (`year=yyyy`, `month=mm`, `day=dd`):

```
<endpoint>/<project name = log_analytics>/<aws account name>/year=yyyy/month=mm/day=dd/<instanceId or Hostname>
```

Resolved for this lab (account `prod-nonpci` shown):

```
http://rustfs:9000/log_analytics/prod-nonpci/year=2026/month=08/day=03/es-node-1/
```

The base path is derived from `.env`:

- `S3_PROJECT_NAME` (log_analytics — first path element)
- `S3_REGION` (af-south-1)
- date segments from the day the repository is (re)registered (`date +%Y/%m/%d`)

#### 5. Snapshot Lifecycle Management:

`make s3-snapshots` also registers the `logs-slm` SLM policy:

- schedule: daily at 01:00 UTC (`0 0 1 * * ?`)
- indices: `logs-prod-nonpci-*` (the simulated account's feeds; override with
  `SLM_INDICES=...`)
- repository: `prod-nonpci` (override with `SLM_REPOSITORY=...`)
- retention: keep 5–50 snapshots, expire after 30 days

Ad-hoc snapshot of all log indices into a classification repository:

```bash
curl -X PUT "localhost:9200/_snapshot/prod-nonpci/snap-$(date +%Y%m%d)" \
  -H 'Content-Type: application/json' \
  -d '{"indices": "logs-prod-nonpci-*", "ignore_unavailable": true}'
```

## Security Considerations:

- All connectors should implement appropriate security controls
- Access to different buckets should be restricted based on classification
- Audit logs should track access to different security classifications
- Compliance requirements should be enforced at the connector level
