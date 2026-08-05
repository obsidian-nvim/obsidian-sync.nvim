SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help
PROJECT_NAME = "obsidian-sync.nvim"
MINITEST = deps/mini.test

NVIM ?= nvim
VIMRUNTIME ?= $(shell $(NVIM) --clean --headless +'lua io.write(vim.env.VIMRUNTIME)' +q 2>/dev/null)

################################################################################
##@ Start here
.PHONY: chores
chores: style lint types test ## Run development tasks (lint, style, types, test); PRs must pass this.

################################################################################
##@ Development
.PHONY: lint
lint: ## Lint the code with selene
	selene --config selene/config.toml lua/ tests/

.PHONY: style
style:  ## Format the code with stylua
	stylua --check .

.PHONY: types
types: ## Type check with EmmyLua
	VIMRUNTIME=$(VIMRUNTIME) emmylua_check ./lua/ --config .emmyrc.json

.PHONY: test
test: $(MINITEST) ## Run unit tests with mini.test
	nvim --headless --clean --noplugin -u ./tests/minimal_init.lua -c "lua MiniTest.run()"

$(MINITEST):
	mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.test $(MINITEST)

################################################################################
##@ Helpers
.PHONY: help
help:  ## Display this help
	@echo "Welcome to $$(tput bold)${PROJECT_NAME}$$(tput sgr0) 🥳📈🎉"
	@echo ""
	@echo "To get started:"
	@echo "  >>> $$(tput bold)make chores$$(tput sgr0)"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
