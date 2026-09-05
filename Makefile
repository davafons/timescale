.PHONY: build tui test test-swift test-rust lint lint-swift lint-rust format install install-tui install-omarchy uninstall uninstall-tui dev package package-tui icon clean

build:
	./scripts/build-app.sh

tui:
	cargo build --release --locked --bin timescale

test: test-swift test-rust

test-swift:
	swift test

test-rust:
	cargo test --workspace --locked

lint: lint-swift lint-rust

lint-swift:
	swift format lint --strict --recursive Sources Tests Package.swift
	shellcheck -S warning scripts/*.sh

lint-rust:
	cargo fmt --all --check
	cargo clippy --workspace --all-targets --locked -- -D warnings

format:
	swift format format --in-place --recursive Sources Tests Package.swift
	cargo fmt --all

install:
	./scripts/install.sh

install-tui: tui
	install -d "$(HOME)/.local/bin"
	install -m 755 target/release/timescale "$(HOME)/.local/bin/timescale"

install-omarchy:
	./scripts/install-omarchy.sh --local

uninstall:
	./scripts/uninstall.sh

uninstall-tui:
	./scripts/uninstall-tui.sh

dev:
	./scripts/dev.sh

package:
	./scripts/package-release.sh

package-tui:
	./scripts/package-tui.sh "" macos-universal universal

icon:
	./scripts/generate-icon.sh

clean:
	swift package clean
	cargo clean
	rm -rf build dist
