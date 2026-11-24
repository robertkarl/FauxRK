APP := build/RK.app
SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)
FRAMEWORKS := -framework Cocoa -framework ApplicationServices -framework AVFoundation -framework AudioToolbox -framework UserNotifications
SIGN_ID ?= -
.DELETE_ON_ERROR:
.PHONY: all run install test
all: $(APP)/Contents/MacOS/RK
$(APP)/Contents/MacOS/RK: $(SOURCES) $(HEADERS) Info.plist Makefile
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/
	xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -O2 $(SOURCES) $(FRAMEWORKS) -o $@
	codesign --force --sign "$(SIGN_ID)" $(APP)
install: all
	mkdir -p "$(HOME)/Applications"
	ditto $(APP) "$(HOME)/Applications/RK.app"
run: all
	open $(APP)
test:
	@set -e; for test in Tests/*.sh; do "$$test"; done
