.DEFAULT_GOAL := run

GODOT ?= godot4
GODOT_ARGS ?=
SERVER_URL ?=

ifneq ($(strip $(SERVER_URL)),)
export ISHTARIA_SERVER_URL := $(SERVER_URL)
endif

.PHONY: run editor test-face test-connection test-history test-gathering test-fauna test-portals test-menu test-social test-trading test-placed test-magic test-story test-disk-cover test-story-live test-world-view test-characters test-environment test-day-night test-controls build build-arm64 build-windows build-macos build-all help

run:
	"$(GODOT)" --path "$(CURDIR)" $(GODOT_ARGS)

editor:
	"$(GODOT)" --editor --path "$(CURDIR)" $(GODOT_ARGS)

test-connection:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/connection_controls.gd

test-history:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/server_history.gd

test-characters:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_creation.gd

test-face:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_face.gd

test-environment:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/surface_environment.gd

test-gathering:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/gathering_client.gd

test-fauna:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/fauna_client.gd

test-portals:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/portal_client.gd

test-menu:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/escape_menu.gd

test-social:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/social.gd

test-magic:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/magic_client.gd

test-placed:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/placed_client.gd

test-trading:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/trading_client.gd

test-world-view:
	"$(GODOT)" --path "$(CURDIR)" --resolution 1600x900 --script res://tests/world_view.gd

test-story-live:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/story_live.gd

test-disk-cover:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/disk_cover.gd

test-story:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/story_client.gd

test-controls:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_controls.gd

test-day-night:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/day_night.gd

build:
	mkdir -p "$(CURDIR)/build"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Linux "$(CURDIR)/build/ishtaria-client.x86_64"

build-arm64:
	mkdir -p "$(CURDIR)/build"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release "Linux arm64" "$(CURDIR)/build/ishtaria-client.linux-arm64"

build-windows:
	mkdir -p "$(CURDIR)/build"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Windows "$(CURDIR)/build/ishtaria-client.windows-x86_64.exe"

build-macos:
	mkdir -p "$(CURDIR)/build"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release macOS "$(CURDIR)/build/ishtaria-client.macos.zip"

build-all: build build-arm64 build-windows build-macos

help:
	@printf '%s\n' \
		'make [run]  Run the client from local sources' \
		'make editor Open the project in Godot' \
		'make test-connection  Test controls against the local server' \
		'make test-characters  Test character assets and first-run setup' \
		'make test-environment  Test terrain mapping and scenery placement' \
		'make test-day-night  Test solar clock, seasons and lighting' \
		'make test-controls  Test keyboard remapping and mouse camera' \
		'make build  Export the Linux release executable' \
		'make build-arm64  Export the Linux arm64 release executable' \
		'make build-windows  Export the Windows x86-64 executable (unsigned)' \
		'make build-macos  Export the universal macOS app as a zip (unsigned)' \
		'Overrides: GODOT=godot4 SERVER_URL=http://127.0.0.1:7400 GODOT_ARGS="..."'
