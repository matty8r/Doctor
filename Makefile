# Doctor — a Markdown utility for macOS
#
#   make            build Doctor.app into ./build
#   make run        build and launch it
#   make install    copy to /Applications and register with LaunchServices
#   make debug      debug build (faster compile, slower app)
#   make clean

SHELL := /bin/bash

.PHONY: all app run install debug clean icon

all: app

app:
	@CONFIG=release Scripts/build-app.sh

debug:
	@CONFIG=debug Scripts/build-app.sh

run: app
	@open build/Doctor.app

install: app
	@rm -rf /Applications/Doctor.app
	@cp -R build/Doctor.app /Applications/Doctor.app
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f /Applications/Doctor.app
	@echo "Installed to /Applications/Doctor.app"
	@echo "To make it the default Markdown reader: select any .md file in Finder,"
	@echo "press Cmd-I, set 'Open with' to Doctor, then click 'Change All…'."

icon:
	@swift Scripts/GenerateIcon.swift build/AppIcon.icns

clean:
	@rm -rf .build build
