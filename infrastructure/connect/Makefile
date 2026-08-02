.DEFAULT_GOAL := help
include ../.env

IMAGE_NAME=kafka-connect-custom
VERSION=3.2

define HELP

Available commands:

- build: Build this project

endef

export HELP
help:
	@echo "$$HELP"
.PHONY: help

build3.1:
#	docker build -t ${REPO_NAME}/${IMAGE_NAME}:${VERSION} Dockerfile.
	docker build -t ${REPO_NAME}/${IMAGE_NAME}:3.1 . 

build3.2:
	docker build -t ${REPO_NAME}/${IMAGE_NAME}:3.2 -f ./Dockerfile.8.1.2
