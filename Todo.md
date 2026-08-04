# Todo — Elastic Log Analytics Pipeline

Tracking list for the Elastic log-analytics deployment (vcluster `my-vc1` +
Docker Compose Kafka stack). Keep statuses updated as tasks complete.

> **History note:** All work completed in the previous phase (sections 1–8:
> deployment, sink connector, ILM/templates, syslog-ng/Filebeat/FluentBit feeds,
> Makefile, S3 snapshot offload) is archived in **`Done.md`**. The list below
> tracks the current phase only.

Legend: `[ ]` pending · `[x]` done · `[~]` in progress

---

## 9. Kibana integration, dashboards & repo indexing (current phase)

- [ ] Document the Kibana ↔ Elasticsearch integration end-to-end
      (`Deployment/DEPLOY_KIBANA.md`): service wiring, `server.basePath=/kibana`,
      port-forward access, data views, Saved Objects API, dashboard provisioning,
      troubleshooting
- [ ] Provision basic Kibana dashboards for the **3 log feeds**
      (`scripts/configure_kibana_dashboards.sh` + `make kibana-dashboards`):
      per-feed data views + saved searches + visualizations + dashboards for
      `logs-prod-nonpci-syslog` / `-filebeat` / `-fluentbit`
- [ ] Add the required log indices to the **prod-nonpci** ES snapshot repository
      (`scripts/take_snapshot.sh` + `make snapshot`): ad-hoc snapshot of
      `logs-prod-nonpci-*` → `prod-nonpci` (SLM `logs-slm` already targets the
      same indices on a daily 01:00 UTC schedule)
- [ ] Run the above against the live stack once the environment is recovered:
      execute `make deployk8s` (ILM/templates + data views + sink + S3 repos),
      then `make kibana-dashboards` and `make snapshot`; verify the 3 dashboards
      show documents in the Kibana UI

## 10. Environment recovery (blocked — user fixing `card_switch_8583` side first)

- [ ] **Compose reconciliation:** the `elastic` and `card_switch_8583` compose
      projects collide on `broker`/`schema-registry`/`connect`/`control-center`/
      `kcat` container names. Decide coexistence model (user), then restore
      `connect` (ES sink), `syslog-ng`, `filebeat`, `rustfs`; re-create the
      `logs-prod-nonpci-syslog` / `-filebeat` / `-log4j` topics
      (`make createtopics`); note the old syslog/filebeat Kafka messages are lost
      (topics deleted) — only new data will flow
- [ ] **vcluster / ES recovery:** `data/vc1` was deleted → worker `/data` bind
      mounts dangled → ES data dir emptied → cluster hung in "broken node lock".
      Recreate `data/vc1/n1..n3`, `vcluster delete my-vc1` + `vcluster create
      my-vc1 -f vcluster.yml`, re-apply `k8s/` and `make deployk8s`. `.kibana`
      saved objects (incl. data views) are lost and recreated by the deploy
      scripts
- [ ] Post-recovery end-to-end verification: ES green, sink connector RUNNING,
      all 3 indices populated, snapshot in `prod-nonpci` repo, dashboards render
