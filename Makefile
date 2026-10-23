APP = KeepingAwake.app
BIN = $(APP)/Contents/MacOS/KeepingAwake
RES = $(APP)/Contents/Resources
SUDOERS = /etc/sudoers.d/keepingawake

$(BIN): main.swift Info.plist icons/*.png icons/AppIcon.icon/icon.json icons/AppIcon.icon/Assets/*
	mkdir -p $(APP)/Contents/MacOS $(RES)
	swiftc -O main.swift -o $(BIN)
	cp Info.plist $(APP)/Contents/
	cp icons/*.png $(RES)/
	xcrun actool icons/AppIcon.icon --compile $(RES) --platform macosx --minimum-deployment-target 14.0 \
		--app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
	codesign --force --sign - $(APP)

install: $(BIN)
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/

# Manual alternative to the in-app setup: lets the app run exactly `pmset -a disablesleep 0|1` as root without a password.
sudoers:
	@f=$$(mktemp) && \
	echo "$(USER) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > $$f && \
	visudo -cf $$f && \
	sudo install -m 0440 -o root -g wheel $$f $(SUDOERS); \
	rm -f $$f

uninstall:
	-pkill -x KeepingAwake
	rm -rf /Applications/$(APP)
	sudo pmset -a disablesleep 0
	sudo rm -f $(SUDOERS)

clean:
	rm -rf $(APP)
