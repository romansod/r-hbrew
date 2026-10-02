.PHONY: check lint

check: lint

lint:
	shellcheck hbrew.sh install.sh
