.DEFAULT_GOAL := help

define HELP

Available commands:

- pull: 	Pull all source images.

- build: 	Build all images.

endef

export HELP
help:
	@echo "$$HELP"
.PHONY: help


pull: confluent misc

build: connect


###### Build Section ######
confluent:
	docker pull confluentinc/cp-kafka:7.9.6
	docker pull confluentinc/cp-kafka-connect-base:7.9.6
	docker pull confluentinc/cp-schema-registry:7.9.6
	docker pull confluentinc/cp-enterprise-control-center:7.9.6
	docker pull confluentinc/cp-kcat:7.9.6

misc:
	docker pull rustfs/rustfs:latest
	docker pull balabit/syslog-ng:latest
	docker pull docker.elastic.co/beats/filebeat:8.14.0
		
connect:
	cd connect; make build
