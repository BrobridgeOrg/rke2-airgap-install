RKE2_VERSION       ?= v1.35.3+rke2r1
HELM_VERSION       ?=
_UNAME_M           := $(shell uname -m)
ARCH               ?= $(patsubst x86_64,amd64,$(patsubst aarch64,arm64,$(_UNAME_M)))
CNI                ?= canal
INGRESS            ?= traefik
ARTIFACTS_BASE_URL ?=
_BUILD_OS_ID      := $(shell . /etc/os-release 2>/dev/null && printf '%s' "$${ID:-}")
_BUILD_OS_VER     := $(shell . /etc/os-release 2>/dev/null && printf '%s' "$${VERSION_ID%%.*}")
_DEFAULT_TARGET_OS := $(if $(filter ubuntu debian,$(_BUILD_OS_ID)),ubuntu,rhel)
TARGET_OS     := $(or $(strip $(TARGET_OS)),$(_DEFAULT_TARGET_OS))
RKE2_MINOR    := $(shell echo $(RKE2_VERSION) | sed 's/v1\.\([0-9]*\)\..*/\1/')
LINUX_MAJOR   := $(or $(strip $(LINUX_MAJOR)),$(_BUILD_OS_VER),9)
OUT_DIR       ?= output

# gen-config options
CIS                      ?= false
DISABLE_CLOUD_CONTROLLER ?= false
DISABLE_KUBE_PROXY       ?= false
RANCHER_PRIME            ?= false
TIMEZONE                 ?= Asia/Taipei
TLS_SANS                 ?=

# Auto-detect node identity; override in config.env if needed
NODE_NAME := $(or $(strip $(NODE_NAME)),$(shell hostname -s 2>/dev/null))
NODE_IP   := $(or $(strip $(NODE_IP)),$(shell ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1))

# TOKEN: auto-generate and save to config.env if not set
ifeq ($(strip $(TOKEN)),)
TOKEN := $(shell openssl rand -hex 32)
_SAVE_TOKEN := $(shell \
  if [ ! -f config.env ] && [ -f config.env.example ]; then cp config.env.example config.env; fi; \
  if grep -q '^TOKEN=' config.env 2>/dev/null; then \
    perl -i -pe 's/^TOKEN=.*/TOKEN=$(TOKEN)/' config.env; \
  else \
    printf '\nTOKEN=%s\n' '$(TOKEN)' >> config.env; \
  fi)
$(info TOKEN auto-generated and saved to config.env)
endif

ARTIFACTS_DIR := $(OUT_DIR)/artifacts
RPM_REPO_DIR  := $(OUT_DIR)/rpm-repo
BUNDLE        := rke2-airgap-$(RKE2_VERSION)-$(ARCH).tar.gz

_PREPARE_DEPS := fetch config
ifneq ($(TARGET_OS),ubuntu)
_PREPARE_DEPS += rpm-repo
endif

.PHONY: fetch rpm-repo config prepare bundle clean

fetch:
	@if [ "$(TARGET_OS)" != "rhel" ]; then ./bundle/fetch-install.sh --dest $(ARTIFACTS_DIR); fi
	./bundle/fetch-artifacts.sh --version $(RKE2_VERSION) --arch $(ARCH) --cni $(CNI) --ingress $(INGRESS) \
		--target-os $(TARGET_OS) --dest $(ARTIFACTS_DIR) \
		$(if $(ARTIFACTS_BASE_URL),--url $(ARTIFACTS_BASE_URL),)
	./bundle/fetch-helm.sh --arch $(ARCH) --dest $(OUT_DIR)/cmd \
		$(if $(HELM_VERSION),--version $(HELM_VERSION),)

rpm-repo:
	./bundle/build-rpm-repo.sh --rke2-minor $(RKE2_MINOR) --linux-major $(LINUX_MAJOR) --arch $(ARCH) --dest $(RPM_REPO_DIR)

config:
	$(if $(strip $(NODE_IP)),,$(error NODE_IP could not be auto-detected. Set it in config.env: NODE_IP=x.x.x.x))
	$(if $(strip $(NODE_NAME)),,$(error NODE_NAME could not be auto-detected. Set it in config.env: NODE_NAME=hostname))
	./bundle/gen-config.sh \
		--role    server \
		--token   $(TOKEN) \
		--cni     $(CNI) \
		--ingress $(INGRESS) \
		--node-name $(NODE_NAME) \
		--node-ip   $(NODE_IP) \
		$(if $(TLS_SANS),--tls-san "$(TLS_SANS)",) \
		$(if $(filter true,$(CIS)),--cis,) \
		$(if $(filter true,$(DISABLE_CLOUD_CONTROLLER)),--disable-cloud-controller,) \
		$(if $(filter true,$(DISABLE_KUBE_PROXY)),--disable-kube-proxy,) \
		$(if $(filter true,$(RANCHER_PRIME)),--rancher-prime,) \
		$(if $(TIMEZONE),--timezone "$(TIMEZONE)",) \
		--dest $(OUT_DIR)/config-server.yaml
	./bundle/gen-config.sh \
		--role       agent \
		--token      $(TOKEN) \
		--server-url https://$(NODE_IP):9345 \
		$(if $(filter true,$(CIS)),--cis,) \
		--dest $(OUT_DIR)/config-agent.yaml

prepare: $(_PREPARE_DEPS)
	cp -r deploy/. $(OUT_DIR)/
	mkdir -p $(OUT_DIR)/images
	echo "$(RKE2_VERSION)" > $(OUT_DIR)/rke2-version.txt
	@echo ""
	@echo "Output ready at: $(OUT_DIR)"

bundle:
	tar -czf $(BUNDLE) -C $(OUT_DIR) .
	@echo ""
	@echo "Bundle created: $(BUNDLE)"

clean:
	rm -rf $(OUT_DIR) $(BUNDLE)
