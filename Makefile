.DEFAULT_GOAL := run

GODOT ?= godot4
GODOT_ARGS ?=
SERVER_URL ?=

ifneq ($(strip $(SERVER_URL)),)
export ISHTARIA_SERVER_URL := $(SERVER_URL)
endif

.PHONY: run editor test-connection test-characters test-environment test-day-night test-controls build help

run:
	"$(GODOT)" --path "$(CURDIR)" $(GODOT_ARGS)

editor:
	"$(GODOT)" --editor --path "$(CURDIR)" $(GODOT_ARGS)

test-connection:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/connection_controls.gd

test-characters:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_creation.gd

test-environment:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/surface_environment.gd

test-controls:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/character_controls.gd

test-day-night:
	"$(GODOT)" --headless --path "$(CURDIR)" --max-fps 60 --script res://tests/day_night.gd

build:
	mkdir -p "$(CURDIR)/build"
	"$(GODOT)" --headless --path "$(CURDIR)" --export-release Linux "$(CURDIR)/build/ishtaria-client.x86_64"

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
		'Overrides: GODOT=godot4 SERVER_URL=http://127.0.0.1:7400 GODOT_ARGS="..."'
