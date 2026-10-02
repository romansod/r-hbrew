.PHONY: check lint test

check: lint test

lint:
	shellcheck hbrew.sh install.sh tests/stubs/brew tests/stubs/curl tests/stubs/gh

test:
	bats tests
