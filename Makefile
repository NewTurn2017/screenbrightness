PREFIX ?= /usr/local
BIN := vigil
LIB := Sources/Brightness.swift Sources/CLI.swift Sources/Agent.swift Sources/Sleep.swift Sources/Awake.swift
PLIST := com.genie.vigil
LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(PLIST).plist
LOG := $(HOME)/Library/Logs/vigil-agent.log
DOMAIN := gui/$(shell id -u)
SUDOERS := /etc/sudoers.d/vigil
AWAKE_PLIST := com.genie.vigil.awake
AWAKE_LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(AWAKE_PLIST).plist

.PHONY: all test install uninstall hotkey-install hotkey-uninstall sleep-setup sleep-teardown clean

all: $(BIN)

$(BIN): $(LIB) Sources/main.swift
	swiftc -O -o $(BIN) $(LIB) Sources/main.swift

vigil-test: $(LIB) Tests/main.swift
	swiftc -o vigil-test $(LIB) Tests/main.swift

test: vigil-test
	./vigil-test

install: $(BIN)
	install -d "$(PREFIX)/bin"
	install -m 755 $(BIN) "$(PREFIX)/bin/$(BIN)"
	@echo "installed $(PREFIX)/bin/$(BIN)"

uninstall:
	rm -f "$(PREFIX)/bin/$(BIN)"

hotkey-install:
	@test -x "$(PREFIX)/bin/$(BIN)" || { echo "run 'make install' (maybe with sudo, or PREFIX=\$$HOME/.local) first"; exit 1; }
	mkdir -p "$(HOME)/Library/LaunchAgents"
	sed -e 's#__BR_PATH__#$(PREFIX)/bin/$(BIN)#' -e 's#__LOG_PATH__#$(LOG)#' \
		launchd/$(PLIST).plist.template > "$(LAUNCH_AGENT)"
	launchctl bootout $(DOMAIN)/$(PLIST) 2>/dev/null || true
	launchctl bootstrap $(DOMAIN) "$(LAUNCH_AGENT)"
	launchctl kickstart -k $(DOMAIN)/$(PLIST)
	cp launchd/$(AWAKE_PLIST).plist.template "$(AWAKE_LAUNCH_AGENT)"
	launchctl bootout $(DOMAIN)/$(AWAKE_PLIST) 2>/dev/null || true
	launchctl bootstrap $(DOMAIN) "$(AWAKE_LAUNCH_AGENT)"
	@echo "hotkey agent + keep-awake job loaded (awake starts OFF; default key ctrl-opt-cmd-B)."
	@echo "Logs: $(LOG)"

hotkey-uninstall:
	launchctl bootout $(DOMAIN)/$(PLIST) 2>/dev/null || true
	rm -f "$(LAUNCH_AGENT)"
	launchctl bootout $(DOMAIN)/$(AWAKE_PLIST) 2>/dev/null || true
	rm -f "$(AWAKE_LAUNCH_AGENT)"
	@echo "hotkey agent + keep-awake job unloaded"

sleep-setup:
	@u=$${SUDO_USER:-$$(id -un)}; \
		echo "installing sleep-control sudoers rule for user: $$u"; \
		sed "s#__USER__#$$u#" sudoers/vigil.sudoers.template > /tmp/vigil.sudoers
	sudo visudo -cf /tmp/vigil.sudoers
	sudo install -m 0440 -o root -g wheel /tmp/vigil.sudoers "$(SUDOERS)"
	@rm -f /tmp/vigil.sudoers
	@echo "sleep control enabled. Now 'vigil off' enables clamshell (no-sleep), 'vigil on' restores sleep."
	@echo "test: vigil off; pmset -g | grep SleepDisabled   # -> 1 ; then vigil on -> 0"

sleep-teardown:
	sudo rm -f "$(SUDOERS)"
	@echo "sleep control disabled (removed $(SUDOERS)). vigil off/on no longer touch sleep."

clean:
	rm -f $(BIN) vigil-test
