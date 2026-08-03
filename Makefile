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
					  Elastic (ILM/templates + data views) and the Kafka ES
					  sink connector

	make sink			- (Re)configure the Kafka Connect Elasticsearch sink
					  connector (requires ES reachable via port-forward)

	make elastic-setup	- (Re)configure Elasticsearch (ILM/templates) + Kibana
					  data views

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
		syslog-ng rustfs \
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
# then configures Elasticsearch (ILM/index templates) + Kibana data views and
# finally registers the Kafka Connect Elasticsearch sink connector so the
# syslog-topic + filebeat-logs streams land in ES.
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

	@echo "🚀 Configuring the Kafka Connect Elasticsearch sink connector..."
	make sink

	@echo "✅ ... k8s stack deployed and pipeline configured"
.PHONY: deployk8s


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

