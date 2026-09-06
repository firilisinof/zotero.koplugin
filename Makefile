# Development helpers for the Zotero KOReader plugin.
#
# The plugin is developed against a KOReader source checkout built for the
# desktop emulator. `make setup` bootstraps that checkout once; afterwards
# `make run` and `make test` exercise the code straight from this directory,
# because KOReader symlinks its whole plugins/ and spec/ trees into the build.
# Editing a .lua file here takes effect without rebuilding.

KOREADER_SRC ?= $(abspath $(CURDIR)/../koreader)

PLUGIN_LINK := $(KOREADER_SRC)/plugins/zotero.koplugin
SPEC_LINK := $(KOREADER_SRC)/spec/unit/zoteroapi_spec.lua

# KOReader's build system expects GNU tools. Put them on PATH here so no shell
# setup is needed to run these targets.
GNU_PATH := $(shell $(CURDIR)/tools/gnu-path.sh 2>/dev/null)
ifneq ($(GNU_PATH),)
export PATH := $(GNU_PATH):$(PATH)
endif

.PHONY: help setup link unlink build run test

help:
	@echo "make setup   Install prerequisites, clone and build KOReader, link this plugin"
	@echo "make link    Link the plugin and its specs into \$$KOREADER_SRC"
	@echo "make unlink  Remove those links"
	@echo "make build   Rebuild the KOReader emulator"
	@echo "make run     Launch the emulator with the plugin loaded"
	@echo "make test    Run the plugin specs"
	@echo ""
	@echo "KOREADER_SRC = $(KOREADER_SRC)"

setup:
	KOREADER_SRC="$(KOREADER_SRC)" ./tools/setup-dev.sh

link: $(PLUGIN_LINK) $(SPEC_LINK)

$(PLUGIN_LINK):
	@mkdir -p $(dir $@)
	ln -sfn $(CURDIR) $@

$(SPEC_LINK):
	@mkdir -p $(dir $@)
	ln -sfn $(CURDIR)/spec/zoteroapi_spec.lua $@

unlink:
	rm -f $(PLUGIN_LINK) $(SPEC_LINK)

build: check-koreader
	cd $(KOREADER_SRC) && ./kodev build

run: link check-koreader
	cd $(KOREADER_SRC) && ./kodev run

test: link check-koreader
	cd $(KOREADER_SRC) && ./kodev test front zoteroapi

.PHONY: check-koreader
check-koreader:
	@test -x $(KOREADER_SRC)/kodev || { \
		echo "No KOReader checkout at $(KOREADER_SRC). Run 'make setup' first,"; \
		echo "or point KOREADER_SRC at an existing checkout."; \
		exit 1; \
	}
