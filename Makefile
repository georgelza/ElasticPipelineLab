.DEFAULT_GOAL := help
include .env

########################################################################################################################
#
#	make build:	
#		1. will cd into acquirer and call local Makefile with make build, which in turn will call a python/Makefile with make build
#
#
########################################################################################################################

define HELP

Available commands:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Elastic
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🚀 Starting & Stopping:

	make build			- Build all binaries and Docker Containers

	make run			- Start the full 8583 stack (provisions syslog-ng.conf)

	make createtopics	- Create supporting Kakfa topics.

	make down			- Tear everything Down

	make ps				- Show whats running

	make logs			- Show all logs

	make logsf			- Stream all logs

  🚀 Kubernetes:

	make k8s			- Deploy vcluster Kubernetes cluster

	make deployk8s		- Apply k8s/ manifests, wait for rollouts, configure
					  Elastic (ILM/templates + data views), the Kafka ES
					  sink connector and the S3 snapshot repositories
					  + SLM policy

	make apply-k8s-layer LAYER=n - Apply one k8s layer by prefix (n = 1..4):
					  1 = Elastic, 2 = Kibana, 3 = FluentBit,
					  4 = Traefik (e.g. `make apply-k8s-layer LAYER=4`)

	make sink			- (Re)configure the Kafka Connect Elasticsearch sink
					  connector (requires ES reachable via port-forward)

	make elastic-setup	- (Re)configure Elasticsearch (ILM/templates) + Kibana
					  data views

	make kibana-dashboards	- Provision the per-feed Kibana dashboards (syslog /
					  filebeat / fluentbit data views + saved searches +
					  visualizations + dashboards)

	make snapshot		- Take an ad-hoc snapshot of logs-prod-nonpci-* into
					  the prod-nonpci S3 repository

	make s3-snapshots	- (Re)configure the RustFS S3 snapshot repositories
					  (one per security classification bucket) + the
					  logs-slm SLM policy (requires ES reachable via
					  port-forward and the RustFS :9000 API published)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

endef

export HELP
help:
	@echo "$$HELP"
.PHONY: help


build:
	@cd infrastructure && make build
.PHONY: build


k8s:
	@echo "🚀 Creating vcluster Kubernetes cluster..."
	sudo vcluster create my-vc1 -f vcluster.yml
	@echo "✅ ... vcluster cluster created successfully"
.PHONY: k8s


run:
	@echo "🚀 Precreating required volumes..."

	mkdir -p ./data/rustfs
	mkdir -p ./data/syslog-ng/config/log
	mkdir -p ./data/vc1

	@echo "🚀 Provisioning syslog-ng.conf from infrastructure/syslog-ng/..."
	cp infrastructure/syslog-ng/syslog-ng.conf ./data/syslog-ng/config/syslog-ng.conf

	docker compose -p elastic up -d \
		broker schema-registry control-center connect \
		syslog-ng filebeat rustfs \
		--remove-orphans

	sleep 5
	make createtopics

	@echo "✅ ... Supporting Infrastructure Started successfully"

.PHONY: run


createtopics:
	cd scripts; ./cre_topics.sh
.PHONY: createtopics


# ── Kubernetes deployment (vcluster "my-vc1") ────────────────────────────────
# Applies the k8s/ manifests in order, waits for the Elastic stack to come up,
# then configures Elasticsearch (ILM/index templates) + Kibana data views, the
# Kafka Connect Elasticsearch sink connector (so the logs-* topic streams land
# in ES) and finally the RustFS S3 snapshot repositories + SLM policy.
deployk8s:
	@echo "🚀 Applying k8s/ manifests (namespace, storage, ES, Kibana, FluentBit, Traefik)..."
	kubectl apply -f k8s/

	@echo "🚀 Waiting for Elasticsearch (elasticsearch-1, elasticsearch-2) + Kibana rollouts..."
	kubectl rollout status deployment/elasticsearch-1 -n elastic --timeout=300s
	kubectl rollout status deployment/elasticsearch-2 -n elastic --timeout=300s
	kubectl rollout status deployment/kibana -n elastic --timeout=300s
	sleep 10

	@echo "🚀 Configuring Elasticsearch (ILM policy + index templates) and Kibana data views..."
	make elastic-setup

	@echo "🚀 Provisioning the per-feed Kibana dashboards (syslog / filebeat / fluentbit)..."
	make kibana-dashboards

	@echo "🚀 Configuring the Kafka Connect Elasticsearch sink connector..."
	make sink

	@echo "🚀 Configuring the RustFS S3 snapshot repositories + SLM policy..."
	make s3-snapshots

	@echo "✅ ... k8s stack deployed and pipeline configured"
.PHONY: deployk8s


# Apply a single k8s layer by its numeric prefix (1=Elastic, 2=Kibana,
# 3=FluentBit, 4=Traefik). Usage: make apply-k8s-layer LAYER=3
# NOTE: the glob must stay QUOTED — shell-expanded globs ("k8s/3.*") are
# rejected by kubectl ("error: Unexpected args"); kubectl expands the pattern
# itself when it is passed quoted.
apply-k8s-layer:
	@test -n "$(LAYER)" || (echo "Usage: make apply-k8s-layer LAYER=n (1..4)" && exit 1)
	@echo "🚀 Applying k8s layer $(LAYER) (k8s/$(LAYER).*)..."
	kubectl apply -f "k8s/$(LAYER).*"
	@echo "✅ ... k8s layer $(LAYER) applied"
.PHONY: apply-k8s-layer


# Standalone: Elasticsearch ILM/templates + Kibana data views.
elastic-setup:
	@echo "🚀 Running Elastic/Kibana configuration (scripts/configure_elastic.sh)..."
	cd scripts && ./configure_elastic.sh
	@echo "✅ ... Elastic/Kibana configured"
.PHONY: elastic-setup


# Standalone: (re)register the Kafka Connect ES sink connector.
sink:
	@echo "🚀 Configuring Kafka Connect ES sink connector (scripts/configure_es_sink.sh)..."
	cd scripts && ./configure_es_sink.sh
	@echo "✅ ... ES sink connector configured"
.PHONY: sink


# Standalone: provision the per-feed Kibana dashboards.
kibana-dashboards:
	@echo "🚀 Provisioning Kibana dashboards (scripts/configure_kibana_dashboards.sh)..."
	cd scripts && ./configure_kibana_dashboards.sh
	@echo "✅ ... Kibana dashboards provisioned"
.PHONY: kibana-dashboards


# Standalone: ad-hoc snapshot of the account's log indices into the prod-nonpci
# repository (SLM logs-slm covers the same indices daily at 01:00 UTC).
snapshot:
	@echo "🚀 Taking ad-hoc snapshot of $(or $(SNAPSHOT_INDICES),logs-prod-nonpci-*) → $(or $(SNAPSHOT_REPO),prod-nonpci) (scripts/take_snapshot.sh)..."
	cd scripts && ./take_snapshot.sh
	@echo "✅ ... snapshot taken"
.PHONY: snapshot


# Standalone: (re)register the RustFS S3 snapshot repositories (eight
# security-classification buckets) + the logs-slm SLM policy.
s3-snapshots:
	@echo "🚀 Configuring RustFS S3 snapshot repositories + SLM (scripts/configure_s3_snapshots.sh)..."
	cd scripts && ./configure_s3_snapshots.sh
	@echo "✅ ... S3 snapshot repositories + SLM configured"
.PHONY: s3-snapshots



# Utility commands
down:
	@echo "🚀 Tear down full stack..."
	docker compose -p elastic down  -v
	
	cd ./data; rm -rf rustfs
	cd ./data/syslog-ng/config; rm -rf log
	cd ./data; rm -rf vc1
	
ps:
	docker compose -p elastic ps

logs:
	docker compose -p elastic logs

logsf:
	docker compose -p elastic logs -f

watch:
	watch docker compose -p elastic ps

