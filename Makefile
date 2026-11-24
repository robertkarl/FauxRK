APP := build/FauxRK.app
EXECUTABLE := $(APP)/Contents/MacOS/FauxRK
HELPER := $(APP)/Contents/Helpers/fauxrk-helper
ICON := $(APP)/Contents/Resources/FauxRK.icns
SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)
HOST_SOURCES := $(addprefix Sources/,RKLocalHost.m RKCore.m RKMonitor.m RKPaneScreen.m RKHelper.m RKRemoteTerminal.m)
FRAMEWORKS := -framework Cocoa -framework ApplicationServices -framework AVFoundation -framework AudioToolbox -framework UserNotifications
OBJCFLAGS := -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -O2 -ISources
SIGN_ID ?= -
.DELETE_ON_ERROR:
.PHONY: all run install test
all: $(EXECUTABLE)
$(HELPER): Helper/main.m $(HOST_SOURCES) $(HEADERS) Makefile
	mkdir -p $(@D)
	xcrun clang $(OBJCFLAGS) Helper/main.m $(HOST_SOURCES) -framework Cocoa -framework ApplicationServices -o $@
	codesign --force --sign "$(SIGN_ID)" $@
$(ICON): Assets/Four-Tine\ Fork\ Scan\ Icon.png scripts/app-icon.sh
	scripts/app-icon.sh "$<" "$@"
$(EXECUTABLE): $(SOURCES) $(HEADERS) Info.plist Makefile $(HELPER) $(ICON)
	mkdir -p $(@D)
	cp Info.plist $(APP)/Contents/
	xcrun clang $(OBJCFLAGS) $(SOURCES) $(FRAMEWORKS) -o $@
	codesign --force --sign "$(SIGN_ID)" $(APP)
install: all
	mkdir -p "$(HOME)/Applications"
	ditto $(APP) "$(HOME)/Applications/FauxRK.app"
run: all
	open $(APP)
test:
	@set -e; for test in Tests/*.sh; do "$$test"; done
