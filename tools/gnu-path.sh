#!/usr/bin/env bash
#
# Prints the PATH prefix that puts Homebrew's GNU tools ahead of the BSD ones
# macOS ships. KOReader's build system (kodev, its Makefiles) requires GNU
# getopt, find, make and friends.
#
# Single source of truth: both the Makefile and tools/setup-dev.sh use this.

set -euo pipefail

brew_prefix="$(brew --prefix)"

# Exactly the four KOReader's doc/Building.md asks for. Do NOT add binutils:
# its GNU ar writes archives Apple's ld rejects with "invalid control bits",
# which breaks the freetype2 link against brotli.
prefixes=(
    "${brew_prefix}/opt/findutils/libexec/gnubin"
    "${brew_prefix}/opt/make/libexec/gnubin"
    "${brew_prefix}/opt/gnu-getopt/bin"
    "${brew_prefix}/opt/util-linux/bin"
    "${brew_prefix}/opt/util-linux/sbin"
)

(IFS=:; printf '%s\n' "${prefixes[*]}")
