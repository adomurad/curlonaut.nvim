PLENARY_PATH ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim
export PLENARY_PATH

.PHONY: test test-unit test-e2e deps

test:
	@./run_tests.sh

test-unit:
	@./run_tests.sh tests/specs/unit

test-e2e:
	@./run_tests.sh tests/specs/e2e

deps:
	@mkdir -p $(dir $(PLENARY_PATH))
	@test -d $(PLENARY_PATH) || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_PATH)
