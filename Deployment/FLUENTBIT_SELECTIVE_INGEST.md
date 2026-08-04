# FluentBit Configuration for Kubernetes

This document describes how to configure the Kubernetes FluentBit daemonset to selectively ingest logs from specific services or namespaces and publish to Kafka.

## Selective Ingestion Configuration

### 1. Namespace-based Filtering

To filter logs by namespace, modify the FluentBit configuration in `k8s/3.01.fluent-bit-config.yaml`:

```yaml
[FILTER]
    Name        kubernetes
    Match       *
    K8S-Parser  on
    K8S-Logging_Enable    Off
    # Keep if namespace matches whitelist
    Regex        ^(prod|finance|banking)$   # <-- change to your whitelist
```

### 2. Label-based Filtering

To filter logs by pod labels, such as `app=payment-service`:

```yaml
[FILTER]
    Name        kubernetes
    Match       *
    K8S-Parser  on
    K8S-Logging_Enable    Off
    # Keep if pod label matches whitelist
    Regex        ^(payment-service|order-service)$
```

### 3. Combined Filtering

To create a more complex filtering rule that applies multiple criteria:

```yaml
[FILTER]
    Name        kubernetes
    Match       *
    K8S-Parser  on
    K8S-Logging_Enable    Off
    # Combine multiple filters using regex
    Regex        ^(prod|finance).*payment-service$
```

### 4. Complete Configuration Example

Here's an updated version of the configuration that includes selective filtering:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: elastic
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush     1
        Log_Level info

    [INPUT]
        Name        tail
        Path        /var/log/containers/*.log
        Parser      cri-log
        Tag         kube.*
        Refresh_Interval 5
        Skip_Long_Lines On

    [INPUT]
        Name        tail
        Path        /var/log/*.log
        Exclude_Path /var/log/containers/*
        Refresh_Interval 5

    [FILTER]
        Name        kubernetes
        Match       *
        K8S-Parser  on
        Merge_Log   On
        K8S-Logging_Enable    On
        K8S-Logging_Json        On
        # Additional Kubernetes metadata enrichment
        Add_Kubernetes_Labels   On
        Add_Kubernetes_Namespace   On

    # Filter for specific namespaces and services
    [FILTER]
        Name        kubernetes
        Match       *
        K8S-Parser  on
        K8S-Logging_Enable    Off
        # Whitelist specific namespaces or services
        Regex        ^(prod|finance|banking)$

    [FILTER]
        Name modify
        Match *
        Rename time @timestamp
        Add source k8s-fluent-bit
        # Add custom fields based on namespace or labels
        Add namespace ${kubernetes_namespace}
        Add service ${kubernetes_label_app}

    [OUTPUT]
        Name kafka
        Match *
        brokers broker:29092
        topics logs-prod-nonpci-fluentbit
        format json
        # Include metadata fields for downstream filtering
        # These can be used as Kafka headers to match on downstream consumers
        header namespace ${kubernetes_namespace}
        header service ${kubernetes_label_app}
```

> **Base config vs. example.** The `[INPUT]` blocks, the final `modify` filter
> (`Rename time @timestamp` / `Add source k8s-fluent-bit`) and the `[OUTPUT]`
> block are the **deployed** configuration — they must stay identical to
> `k8s/3.01.fluent-bit-config.yaml`. The two `[FILTER] Name kubernetes` blocks
> above are the **selective-ingest addition** shown by this guide: if you apply
> them, keep the deployed `modify` filter in place (it is what produces the
> `@timestamp` field the data views rely on) and do not remove the `source`
> tag or the Kafka output. `k8s/3.01.fluent-bit-config.yaml` itself contains
> only the `modify` filter — no `kubernetes` filter.

### 5. Implementation Steps

1. **Update ConfigMap**: Apply the modified configuration to your Kubernetes cluster:

   ```bash
   kubectl apply -f k8s/3.01.fluent-bit-config.yaml
   ```

2. **Restart FluentBit**: Ensure the daemonset picks up the new configuration:

   ```bash
   kubectl delete pods -n elastic -l app=fluent-bit
   ```

3. **Verification**: Check that the new configuration is working properly:

   ```bash
   kubectl logs -n elastic -l app=fluent-bit
   ```

## Implementation Notes

1. **Filter Placement**:

   - The Kubernetes filter should be applied **after** the standard Kubernetes metadata enrichment
   - The regex filter should be applied **after** all Kubernetes metadata is present in the log record

2. **Filter Syntax**:

   - The regex pattern matches against the field specified in the filter key (e.g., `kubernetes_namespace`)
   - Multiple or complex regexes can be applied using the basic regex engine included with FluentBit

3. **Performance Impact**:

   - Filtering operations occur in each Log record processing path
   - This adds minimal overhead to existing FluentBit processing
   - The filter is applied to each log line before it's output by FluentBit

This configuration allows the Kubernetes environment to selectively forward only logs from specified namespaces or services to Kafka, while maintaining all necessary metadata for downstream processing.