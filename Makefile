# The Command Line Tools need the Swift Testing macro plugin path spelled out.
PLUGINS = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(PLUGINS)

# Every window switch is logged; the log of the current run is kept for debugging.
run:
	swift run Tessera 2>&1 | tee tessera.log

.PHONY: test run zip

# A zip to hand on: the release binary plus the how-to text.
zip:
	swift build -c release
	rm -rf dist && mkdir -p dist/Tessera
	cp .build/release/Tessera "How to run Tessera.txt" dist/Tessera/
	cd dist && zip -qr Tessera.zip Tessera
