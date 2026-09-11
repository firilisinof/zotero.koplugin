# Development helpers for the Zotero KOReader plugin.
#
# The plugin is developed against a KOReader source checkout built for the
# desktop emulator. `make setup` bootstraps that checkout once; afterwards
# `make run` and `make test` exercise the code straight from this directory,
# because KOReader symlinks its whole plugins/ and spec/ trees into the build.
# Editing a .lua file here takes effect without rebuilding.

KOREADER_SRC ?= $(abspath $(CURDIR)/../koreader)

PLUGIN_LINK := $(KOREADER_SRC)/plugins/zotero.koplugin

# Every spec/*_spec.lua is linked into KOReader's shared spec/unit directory,
# and its basename is the name kodev uses to select the test.
SPEC_SOURCES := $(wildcard $(CURDIR)/spec/*_spec.lua)
SPEC_LINKS := $(patsubst $(CURDIR)/spec/%,$(KOREADER_SRC)/spec/unit/%,$(SPEC_SOURCES))
SPEC_NAMES := $(patsubst %_spec.lua,%,$(notdir $(SPEC_SOURCES)))

# KOReader's build system expects GNU tools. Put them on PATH here so no shell
# setup is needed to run these targets.
GNU_PATH := $(shell $(CURDIR)/tools/gnu-path.sh 2>/dev/null)
ifneq ($(GNU_PATH),)
export PATH := $(GNU_PATH):$(PATH)
endif

.PHONY: help setup link unlink build run test package

help:
	@echo "make setup   Install prerequisites, clone and build KOReader, link this plugin"
	@echo "make link    Link the plugin and its specs into \$$KOREADER_SRC"
	@echo "make unlink  Remove those links"
	@echo "make build   Rebuild the KOReader emulator"
	@echo "make run     Launch the emulator with the plugin loaded"
	@echo "make test    Run the plugin specs"
	@echo "make package Create dist/zotero.koplugin.zip for installation"
	@echo ""
	@echo "KOREADER_SRC = $(KOREADER_SRC)"

setup:
	KOREADER_SRC="$(KOREADER_SRC)" ./tools/setup-dev.sh

link: $(PLUGIN_LINK) $(SPEC_LINKS)

$(PLUGIN_LINK):
	@mkdir -p $(dir $@)
	ln -sfn $(CURDIR) $@

$(KOREADER_SRC)/spec/unit/%_spec.lua: $(CURDIR)/spec/%_spec.lua
	@mkdir -p $(dir $@)
	ln -sfn $< $@

unlink:
	rm -f $(PLUGIN_LINK) $(SPEC_LINKS)

build: check-koreader
	cd $(KOREADER_SRC) && ./kodev build

run: link check-koreader
	cd $(KOREADER_SRC) && ./kodev run

test: link check-koreader
	sh ./tools/test.sh "$(KOREADER_SRC)" $(SPEC_NAMES)

package:
	sh ./tools/package.sh

.PHONY: check-koreader
check-koreader:
	@test -x $(KOREADER_SRC)/kodev || { \
		echo "No KOReader checkout at $(KOREADER_SRC). Run 'make setup' first,"; \
		echo "or point KOREADER_SRC at an existing checkout."; \
		exit 1; \
	}
