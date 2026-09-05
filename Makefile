.PHONY: build test install uninstall dev package icon clean

build:
	./scripts/build-app.sh

test:
	swift test

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
