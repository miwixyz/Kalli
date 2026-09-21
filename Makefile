.PHONY: gen build run clean test

APP = MacCal
CONFIG ?= Debug
DERIVED = build

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

run: build
	@pkill -x $(APP) || true
	open $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj
