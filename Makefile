# The Command Line Tools need the Swift Testing macro plugin path spelled out.
PLUGINS = /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
APP = dist/Tessera.app
INSTALL = /Applications/Vibecode

test:
	swift test -Xswiftc -plugin-path -Xswiftc $(PLUGINS)

# The Command Line Tools build no app bundles, so the bundle is put together here.
app:
	swift build -c release
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Tessera $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	cp Tessera.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

# Replaces the installed app and starts it. A changed build needs Accessibility access again.
run: app
	pkill -x Tessera || true
	while pgrep -qx Tessera; do sleep 0.1; done
	mkdir -p $(INSTALL) && rm -rf $(INSTALL)/Tessera.app && cp -R $(APP) $(INSTALL)/
	open $(INSTALL)/Tessera.app

# A zip to hand on: the app plus the how-to text.
zip: app
	rm -rf dist/Tessera dist/Tessera.zip && mkdir dist/Tessera
	cp -R $(APP) "How to open Tessera.txt" dist/Tessera/
	cd dist && zip -qry Tessera.zip Tessera

# Redraws Tessera.icns from scripts/icon.swift.
icon:
	swift scripts/icon.swift .build/Tessera.iconset
	iconutil -c icns .build/Tessera.iconset -o Tessera.icns

.PHONY: test app run zip icon
