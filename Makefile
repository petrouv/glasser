SCRIPT := glasser
INSTALL_DIR := $(HOME)/.local/bin

.PHONY: help install uninstall test test-all test-terminal lint

help:
	@echo "Targets:"
	@echo "  install    symlink $(INSTALL_DIR)/$(SCRIPT) → ./$(SCRIPT)"
	@echo "  uninstall  remove the symlink $(INSTALL_DIR)/$(SCRIPT)"
	@echo "  test       tests under /bin/bash (3.2 on macOS, the target version)"
	@echo "  test-all   tests under /bin/bash and the bash in PATH"
	@echo "  test-terminal  tests under /bin/bash + a real Terminal.app (opens windows)"
	@echo "  lint       shellcheck glasser and run-tests.sh"

install:
	@mkdir -p "$(INSTALL_DIR)"
	@ln -sf "$(CURDIR)/$(SCRIPT)" "$(INSTALL_DIR)/$(SCRIPT)"
	@echo "✓ $(INSTALL_DIR)/$(SCRIPT) → $(CURDIR)/$(SCRIPT)"

uninstall:
	@rm -f "$(INSTALL_DIR)/$(SCRIPT)"
	@echo "✓ removed $(INSTALL_DIR)/$(SCRIPT)"

# Explicit /bin/bash so that run-tests.sh itself runs under 3.2; glasser
# runs under /bin/bash anyway (GLASSER_BASH in run-tests.sh).
test:
	/bin/bash ./run-tests.sh

test-all: test
	GLASSER_BASH=bash bash ./run-tests.sh

# Tests in a real Terminal.app open windows on screen and need the
# "Automation" permission, so they are off by default.
test-terminal:
	GLASSER_TERMINAL_APP=1 /bin/bash ./run-tests.sh

lint:
	shellcheck --shell=bash $(SCRIPT) run-tests.sh
