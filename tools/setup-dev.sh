#!/usr/bin/env bash
#
# One-time bootstrap for local plugin development on macOS.
#
# Installs the KOReader build prerequisites, clones and builds the KOReader
# emulator, then links this repository into that checkout so `make run` and
# `make test` work against the real thing.
#
# Safe to re-run: every step is skipped when it is already done.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
KOREADER_SRC="${KOREADER_SRC:-$(cd "${PLUGIN_DIR}/.." && pwd -P)/koreader}"

BREW_PACKAGES=(
    autoconf automake bash binutils cmake coreutils findutils gettext
    gnu-getopt libtool make meson nasm ninja pkgconf sdl3 util-linux
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

install_prerequisites() {
    if ! command -v brew >/dev/null; then
        echo "Homebrew is required: https://brew.sh" >&2
        exit 1
    fi

    local missing=()
    local pkg
    for pkg in "${BREW_PACKAGES[@]}"; do
        [ -d "$(brew --prefix)/opt/${pkg}" ] || missing+=("${pkg}")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        info "Build prerequisites already installed"
        return
    fi

    info "Installing ${#missing[@]} missing prerequisites: ${missing[*]}"
    brew install "${missing[@]}"
}

clone_koreader() {
    if [ -d "${KOREADER_SRC}/.git" ]; then
        info "KOReader checkout already present at ${KOREADER_SRC}"
        return
    fi

    info "Cloning KOReader into ${KOREADER_SRC}"
    git clone https://github.com/koreader/koreader.git "${KOREADER_SRC}"
}

build_koreader() {
    # kodev needs Homebrew's GNU getopt, find and make rather than the BSD
    # versions macOS ships, or it bails with "unsupported getopt version".
    export PATH="$("${PLUGIN_DIR}/tools/gnu-path.sh"):${PATH}"

    info "Fetching KOReader third party sources (this takes a while)"
    (cd "${KOREADER_SRC}" && ./kodev fetch-thirdparty)

    info "Building the KOReader emulator (30-45 minutes on a cold cache)"
    (cd "${KOREADER_SRC}" && ./kodev build)

    # kodev exits 0 on some failures, so check that the build really landed.
    if ! compgen -G "${KOREADER_SRC}/koreader-emulator-*/koreader/reader.lua" >/dev/null; then
        echo "Build did not produce an emulator tree under ${KOREADER_SRC}." >&2
        exit 1
    fi
}

main() {
    install_prerequisites
    clone_koreader
    build_koreader
    info "Linking the plugin and its specs into ${KOREADER_SRC}"
    make -C "${PLUGIN_DIR}" link
    info "Done. Run 'make test' or 'make run'."
}

main "$@"
