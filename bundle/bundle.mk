RKE2_VERSION       ?= v1.35.3+rke2r1
ARCH               ?= amd64
CNI                ?= canal
INGRESS            ?= traefik
ARTIFACTS_BASE_URL ?=
RKE2_MINOR    := $(shell echo $(RKE2_VERSION) | sed 's/v1\.\([0-9]*\)\..*/\1/')
LINUX_MAJOR   ?= 9
OUT_DIR       ?= output

# gen-config options
ROLE                    ?= server
CIS                     ?= false
DISABLE_CLOUD_CONTROLLER ?= false
DISABLE_KUBE_PROXY       ?= false
TOKEN      ?=
NODE_NAME  ?=
NODE_IP    ?=
SERVER_URL ?=
TLS_SANS   ?=
REGISTRY   ?=

ARTIFACTS_DIR := $(OUT_DIR)/artifacts
RPM_REPO_DIR  := $(OUT_DIR)/rpm-repo
BUNDLE        := rke2-airgap-$(RKE2_VERSION)-$(ARCH).tar.gz

.PHONY: fetch rpm-repo config prepare bundle clean

fetch:
	./bundle/fetch-install.sh --dest $(ARTIFACTS_DIR)
	./bundle/fetch-artifacts.sh --version $(RKE2_VERSION) --arch $(ARCH) --cni $(CNI) --ingress $(INGRESS) --dest $(ARTIFACTS_DIR) \
		$(if $(ARTIFACTS_BASE_URL),--url $(ARTIFACTS_BASE_URL),)

rpm-repo:
	./bundle/build-rpm-repo.sh --rke2-minor $(RKE2_MINOR) --linux-major $(LINUX_MAJOR) --arch $(ARCH) --dest $(RPM_REPO_DIR)

config:
	$(if $(TOKEN),,$(error TOKEN is required. Set it in .env or via: make config TOKEN=...))
	$(if $(NODE_NAME),,$(error NODE_NAME is required. Set it in .env or via: make config NODE_NAME=...))
	$(if $(NODE_IP),,$(error NODE_IP is required. Set it in .env or via: make config NODE_IP=...))
	./bundle/gen-config.sh \
		--role    $(ROLE) \
		--token   $(TOKEN) \
		--cni     $(CNI) \
		--dest    $(OUT_DIR)/config.yaml \
		--ingress $(INGRESS) \
		$(if $(NODE_NAME),--node-name $(NODE_NAME),) \
		$(if $(NODE_IP),--node-ip $(NODE_IP),) \
		$(if $(SERVER_URL),--server-url $(SERVER_URL),) \
		$(if $(TLS_SANS),--tls-san "$(TLS_SANS)",) \
		$(if $(filter true,$(CIS)),--cis,) \
		$(if $(filter true,$(DISABLE_CLOUD_CONTROLLER)),--disable-cloud-controller,) \
		$(if $(filter true,$(DISABLE_KUBE_PROXY)),--disable-kube-proxy,) \
		$(if $(REGISTRY),--registry $(REGISTRY),)

prepare: fetch rpm-repo config
	cp -r deploy/. $(OUT_DIR)/
	@echo ""
	@echo "Output ready at: $(OUT_DIR)"

bundle:
	tar -czf $(BUNDLE) -C $(OUT_DIR) .
	@echo ""
	@echo "Bundle created: $(BUNDLE)"

clean:
	rm -rf $(OUT_DIR) $(BUNDLE)
