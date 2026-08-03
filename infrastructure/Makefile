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


pull: confluent

build: connect rustfs


###### Build Section ######
confluent:
	docker pull confluentinc/cp-kafka:7.9.6
	docker pull confluentinc/cp-kafka-connect-base:7.9.6
	docker pull confluentinc/cp-schema-registry:7.9.6
	docker pull confluentinc/cp-enterprise-control-center:7.9.6
	docker pull confluentinc/cp-kcat:7.9.6
	
connect:
	cd connect; make build

rustfs:
	cd rustfs; make build