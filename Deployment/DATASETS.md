# Data Sets and Topic Management

## Topic Configuration and Source Feeds

The system uses multiple topics to manage different data sources:

### Current Topics:

- `syslog-topic`: For syslog-ng forwarded logs
- `filebeat-logs`: For Filebeat in Docker Compose
- `filebeat-topic`: For Filebeat (non-Docker Compose)  
- `fluent-bit-logs`: For FluentBit logs
- `syslog-topic-*`: For various syslog classifications

### Source Feed Configuration:

Topics are configured in:

1. **Syslog-ng Config** (`conf/syslog-ng-config/syslog-ng.conf`):

   ```
   topic("syslog-topic")
   ```

2. **Filebeat Config** (`conf/filebeat.yml`):

   ```
   topic: "filebeat-logs"
   ```

3. **FluentBit Config** (`k8s/fluent-bit-config.yaml`):

   ```
   topics filebeat-logs
   ```

4. **Docker Compose** (`docker-compose.yml`):

   - Topics defined through connector configuration

### Sink Configuration:

All sources are currently consumed by a single Elasticsearch sink connector defined in:

- `elasticsearch-sink-connector.yaml` or Kubernetes ConfigMap
- Example: `topics=syslog-topic`

## Multi-Bucket Segmentation by Security Classification

Yes, the Elastic "database" can be split into multiple buckets by security classifications including:

### Security Classifications:

1. **Production vs Non-Production**
2. **PCI vs Non-PCI** 
3. **IFE (Internet Facing Exposed)**
4. **Unregulated**

### Implementation Approach:

#### 1. Topic-based Segregation:

Create separate topics for each classification:

- `syslog-topic-prod-pci` (Production-PCI)
- `syslog-topic-prod-nonpci` (Production-NonPCI)
- `syslog-topic-prod-pci-ife` (Production PCI IFE data)
- `syslog-topic-prod-nonpci-ife` (Production NonPCI IFE data)
- `syslog-topic-nonprod-pci` (Non-Production-PCI)
- `syslog-topic-nonprod-nonpci` (Non-Production-NonPCI)
- `syslog-topic-nonprod-pci-ife` (Non-Production PCI IFE data)
- `syslog-topic-nonprod-nonpci-ife` (Non-Production NonPCI IFE data)
- `syslog-topic-prod-unregulated` (Production Unregulated data)
- `syslog-topic-nonprod-unregulated` (Non_Production Unregulated data)
- `syslog-topic-network` (Network data)
- ...

#### 2. Connector-based Bucket Assignment:

Deploy separate Elasticsearch sink connectors:

- `elasticsearch-sink-prod` → Production Elasticsearch cluster/bucket
- `elasticsearch-sink-nonprod` → Staging Elasticsearch cluster/bucket
- `elasticsearch-sink-pci` → PCI-compliant Elasticsearch cluster/bucket
- `elasticsearch-sink-nonpci` → Non-PCI Elasticsearch cluster/bucket
- `elasticsearch-sink-prod-ife` → Production PCI Elasticsearch cluster/bucket
- `elasticsearch-sink-nonprod-ife` → Non-Prod IFE Elasticsearch cluster/bucket
- `elasticsearch-sink-unregulated` → Non-PCI Elasticsearch cluster/bucket


#### 3. Implementation Steps:

1. **Configuration Changes**:

   - Modify source configurations to use appropriate topics
   - Update Kafka source configurations to specify new topics

2. **Deployment Modifications**:

   - Deploy multiple connectors with different topic assignments
   - Configure separate Elasticsearch clusters/indices for each classification

3. **Topic Management**:

   - Create distinct Kafka topics for each classification
   - Implement appropriate retention policies per classification

#### 4. S3 Storage Organization:

The directory structure follows the convention:

```
<S3 endpoint>/<project name>/<aws account name>/year=<year>/month=<month>/day=<day>/<instanceId or Hostname>/<security_classification>
```

## Security Considerations:

- All connectors should implement appropriate security controls
- Access to different buckets should be restricted based on classification
- Audit logs should track access to different security classifications
- Compliance requirements should be enforced at the connector level