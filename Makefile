NAME=controller
VERSION=$(shell git rev-parse HEAD)
SEMVER_VERSION=$(shell grep version Cargo.toml | awk -F"\"" '{print $$2}' | head -n 1)
REPO=clux
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

install:
	cargo run --bin crdgen > yaml/foo-crd.yaml
	kubectl apply -f yaml/foo-crd.yaml

run:
	OPENTELEMETRY_ENDPOINT_URL=https://0.0.0.0:55680 RUST_LOG=info,kube=trace,controller=debug cargo run --features=telemetry

compile:
	docker run --rm \
		-v cargo-cache:/root/.cargo \
		-v $$PWD:/volume \
		-w /volume \
		-it clux/muslrust:stable \
		cargo build --release
	sudo chown $$USER:$$USER -R target
	mv target/x86_64-unknown-linux-musl/release/controller .

build:
	docker build -t $(REPO)/$(NAME):$(VERSION) .

tag-latest: build
	docker tag $(REPO)/$(NAME):$(VERSION) $(REPO)/$(NAME):latest
	docker push $(REPO)/$(NAME):$(VERSION)
	docker push $(REPO)/$(NAME):latest

tag-semver: build
	if curl -sSL https://registry.hub.docker.com/v1/repositories/$(REPO)/$(NAME)/tags | jq -r ".[].name" | grep -q $(SEMVER_VERSION); then \
		echo "Tag $(SEMVER_VERSION) already exists - not publishing" ; \
	else \
		docker tag $(REPO)/$(NAME):$(VERSION) $(REPO)/$(NAME):$(SEMVER_VERSION) ; \
		docker push $(REPO)/$(NAME):$(SEMVER_VERSION) ; \
	fi

# Helpers for using tempo as an otel collector
forward-tempo-agent:
	kubectl port-forward -n monitoring service/grafana-agent-traces 55680:55680
forward-tempo-chart:
	kubectl port-forward -n monitoring service/promstack-tempo 55680:4317
forward-tempo-metrics:
	kubectl port-forward -n monitoring service/grafana-agent-traces 8080:8080
check-tempo-metrics:
	curl http://0.0.0.0:8080/metrics -s |grep -E "^tempo_receiver_accepted_span"
	# can verify that spans are received from metrics on the grafana-agent-traces
    # tempo_receiver_accepted_spans{receiver="otlp",tempo_config="default",transport="grpc"} 4
