# The Command Line Tools need the Swift Testing macro plugin path spelled out.
PLUGINS = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(PLUGINS)

# Every window switch is logged; the log of the current run is kept for debugging.
run:
	swift run Tessera 2>&1 | tee tessera.log

.PHONY: test run
