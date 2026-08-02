# Integrating Elasticsearch with Jira 

Primarily relies on the Elastic Stack Alerting framework and Kibana's native Jira Connector.

When a rule's condition is met (such as high error rates, unauthorized logins, or metric spikes), Elastic triggers an action via the connector to automatically create an issue in your Jira project.

## Part 1: Defining Rules & Alerts in Elastic

Alerts are created using Kibana's Rules and Actions engine. You can define rules globally or within specific apps like Observability, Security, or Discover.

### Step-by-Step Rule Creation

1. Navigate to Rules:
Go to Stack Management > Alerts and Insights > Rules (or click Alerts inside Kibana Observability/Security).
Click Create rule.

2. Select the Rule Type:
Choose a rule type based on your detection criteria:
Elasticsearch Query: Triggers when specific documents match a KQL/Lucene query or ES|QL expression within a given timeframe.
Index Threshold: Triggers when aggregated field values (e.g., count, avg, max) exceed a baseline.
Log Threshold: Triggers when specific log messages spike.
Anomaly Detection: Triggers based on Machine Learning job outputs.

3. Define Criteria & Check Schedule:
Evaluation Interval: Define how often Kibana evaluates the rule (e.g., every 1m or 5m).
Condition & Time Window: Specify the query filter (e.g., service.name: "payment-api" AND log.level: "error") and lookback time (e.g., last 5 minutes).

4. Set Action Frequency & Flapping Rules:
Configure how often actions trigger to avoid alert fatigue (e.g., On check intervals, On alert status changes, or Custom throttled intervals).

## Part 2: Integrating Jira to Auto-Create Tickets

To enable automatic ticket creation, you must create a Jira Connector and attach it to your rule as an Action.

### 1. Create the Jira Connector in Kibana

*Prerequisite: Jira API token with project write permissions*

1. Go to Stack Management > Connectors in Kibana.

2. Click Create connector and select Jira (or Jira Service Management).

3. Fill in the connection details:

    - URL: Your Jira instance base URL (e.g., [https://yourdomain.atlassian.net](https://yourdomain.atlassian.net)).

    - Project key: The Jira project key where tickets should be created (e.g., DEV or SEC).

    - Email & API Token: User credentials for authentication.

4. Click Test connector to verify the connection, then Save.

### 2. Attach the Jira Action to the Rule

1. Edit your existing alert rule (or add this during rule creation).

2. Scroll to the Actions section and select Jira as the connector.

3. Select Run when: Query matched / Is active.

4. Configure the Jira Issue fields using Mustache variables to pull real-time contextual data from Elastic:

    - Issue Type: Bug, Task, or Incident.

    - Priority: High, Medium, etc.

    - Summary / Title: [Elastic Alert] {{rule.name}} triggered

    - Description: Details summarizing the error payload, query output, timestamp, and deep link.

### 3. Configure Recovery Actions (Optional)

Add a secondary action under the Recovered state to post a comment or auto-update the ticket when the alert condition clears.


## Example Action Payload (Mustache Templating)

When populating the Jira ticket Description field, you can leverage built-in Kibana tokens:

```
Alert Summary: {{rule.name}}
Environment: {{context.environment}}
Triggered Time: {{date}}

Alert Reason: {{context.message}}

View details in Kibana:
{{rule.url}}
```

## Best Practices for Ticket Management

- Deduplication: Kibana manages alert lifecycle state so that a single rule instance doesn't flood Jira with duplicate tickets on every check cycle.
- Throttling: Use Custom action intervals (e.g., run every 15 minutes) if your rule evaluates high-frequency events.
- Mandatory Custom Fields: If your Jira project enforces custom mandatory fields (e.g., Component or Environment), specify them under the connector's Additional fields JSON configuration to avoid Jira API validation errors.