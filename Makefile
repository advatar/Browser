### Development helpers for the GUI/Tauri workspace.

NPM ?= npm
PNPM ?= pnpm
CARGO ?= cargo
GUI_CRATE := gui
GUI_DIR := crates/$(GUI_CRATE)
ORBIT_UI_DIR := orbit-shell-ui
AFM_NODE_CRATE := afm-node
AFM_ZKVM_CRATE := afm-zkvm
ROUTER_PKG := @browser/afm-router
REGISTRY_PKG := @browser/afm-registry
PIPELINES_PKG := @browser/afm-pipelines
MARKETPLACE_PKG := @browser/afm-marketplace

.PHONY: deps tauri-cli dev frontend-build build afm-node afm-node-check zkvm router registry pipelines marketplace workspace-install env-templates

deps: workspace-install
	$(NPM) --prefix $(ORBIT_UI_DIR) install
	$(NPM) --prefix $(GUI_DIR) install

workspace-install:
	$(PNPM) install --ignore-scripts

tauri-cli:
	$(CARGO) install tauri-cli --version '^2' --locked

dev: deps
	$(CARGO) tauri dev -p $(GUI_CRATE)

frontend-build: deps
	$(NPM) --prefix $(ORBIT_UI_DIR) run build

build: frontend-build
	$(CARGO) tauri build -p $(GUI_CRATE)

afm-node:
	$(CARGO) run -p $(AFM_NODE_CRATE) --bin dev

afm-node-check:
	$(CARGO) check -p $(AFM_NODE_CRATE)

zkvm:
	$(CARGO) test -p $(AFM_ZKVM_CRATE)

router:
	$(PNPM) --filter $(ROUTER_PKG) dev

registry:
	$(PNPM) --filter $(REGISTRY_PKG) dev

pipelines:
	$(PNPM) --filter $(PIPELINES_PKG) dev

marketplace:
	$(PNPM) --filter $(MARKETPLACE_PKG) dev

env-templates:
	@ls configs/examples/*.example
