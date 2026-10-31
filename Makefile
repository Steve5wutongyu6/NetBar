# NetBar — build entry points. Every target shells out to Scripts/ so local and
# CI runs stay identical.

SHELL := /bin/bash

.PHONY: all build run test test-engine test-app release snapshot project clean

all: build

build:
	@./Scripts/build.sh --debug

run: build
	@open build/Debug/NetBar.app

test: test-engine test-app

test-engine:
	@cd engine && cargo test --locked && cargo clippy --locked --all-targets -- -D warnings && cargo fmt --check

test-app:
	@./Scripts/build.sh --debug --test

release:
	@./Scripts/package.sh

snapshot: build
	@mkdir -p docs
	@build/Debug/NetBar.app/Contents/MacOS/NetBar --snapshot docs/menu.png \
		--fixture NetBarTests/Fixtures/sample.json

project:
	@python3 Scripts/generate-project.py

clean:
	@rm -rf build dist
	@cd engine && cargo clean
	@echo cleaned
