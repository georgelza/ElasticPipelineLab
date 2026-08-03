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

	make run			- Start the Full 8583 stack	

	make createtopics	- Create supporting Kakfa topics.

	make down			- Tear everything Down

	make ps				- Show whats running

	make logs			- Show all logs

	make logsf			- Stream all logs

  🚀 Kubernetes:

	make k8s			- Deploy vcluster Kubernetes cluster

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

	mkdir -p ./data/elasticsearch
	mkdir -p ./data/rustfs
	mkdir -p ./data/syslog-ng/config/log
	mkdir -p ./data/vc1

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

