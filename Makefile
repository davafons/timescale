.PHONY: build test lint format install uninstall dev package icon clean

build:
	./scripts/build-app.sh

test:
	swift test

lint:
	swift format lint --strict --recursive Sources Tests Package.swift
	shellcheck -S warning scripts/*.sh

format:
	swift format format --in-place --recursive Sources Tests Package.swift

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

dev:
	./scripts/dev.sh

package:
	./scripts/package-release.sh

icon:
	./scripts/generate-icon.sh

clean:
	swift package clean
	rm -rf build dist
