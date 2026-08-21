#!/bin/bash
# ==============================================================================
# Zsh (and ncurses) source build — sudo-less host environments
#
# Builds zsh from source into $PREFIX (default: $HOME/.local), no root required.
# If ncurses headers are missing, ncurses is built into the same prefix first.
#
# Scope: host-only. In Docker, use config/apt-packages.txt + install_zsh.sh
# instead — this script refuses to run inside a container.
#
# Usage:
#   ./install_zsh_from_source.sh [zsh_version]
#
# Env overrides:
#   PREFIX            install prefix                 (default: $HOME/.local)
#   BUILD_DIR         source/build work directory    (default: $PREFIX/src)
#   NCURSES_VERSION   ncurses version if built       (default: 6.5)
#   JOBS              make -j parallelism            (default: nproc)
#
# After this, run ./install_zsh.sh for Oh My Zsh + plugins.
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# --- Constants ----------------------------------------------------------------

readonly ZSH_VERSION_DEFAULT="5.9"
readonly NCURSES_VERSION_DEFAULT="6.5"

readonly ZSH_VERSION="${1:-$ZSH_VERSION_DEFAULT}"
readonly NCURSES_VERSION="${NCURSES_VERSION:-$NCURSES_VERSION_DEFAULT}"

readonly PREFIX="${PREFIX:-$HOME/.local}"
readonly BUILD_DIR="${BUILD_DIR:-$PREFIX/src}"
readonly JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

readonly ZSH_URL="https://www.zsh.org/pub/zsh-${ZSH_VERSION}.tar.xz"
readonly NCURSES_URL="https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"

# --- Preflight ----------------------------------------------------------------

check_environment() {
    if is_docker; then
        log_error "This script targets sudo-less host environments."
        log_error "In Docker, zsh is provided via config/apt-packages.txt + install_zsh.sh."
        return 1
    fi
    log "Host build → PREFIX=$PREFIX  BUILD_DIR=$BUILD_DIR  JOBS=$JOBS"
}

check_build_tools() {
    local missing=()
    for cmd in cc make curl tar xz; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing build tools: ${missing[*]}"
        log_error "Ask admin to install them (e.g. build-essential, xz-utils)."
        return 1
    fi
    log_success "Build tools OK."
}

# Probe the system for a usable <ncurses.h> via the C preprocessor.
system_ncurses_available() {
    echo '#include <ncurses.h>' | cc -E -xc - -o /dev/null 2>/dev/null
}

# --- Fetch --------------------------------------------------------------------

download_and_extract() {
    local url="$1"
    local archive
    archive="$(basename "$url")"

    mkdir -p "$BUILD_DIR"
    if [[ ! -f "$BUILD_DIR/$archive" ]]; then
        log "Downloading $url"
        curl -fL "$url" -o "$BUILD_DIR/$archive"
    else
        log "Cached archive found: $BUILD_DIR/$archive"
    fi

    log "Extracting $archive"
    tar -xf "$BUILD_DIR/$archive" -C "$BUILD_DIR"
}

# --- ncurses ------------------------------------------------------------------

build_ncurses() {
    if [[ -f "$PREFIX/include/ncurses.h" ]]; then
        log_success "ncurses already installed under $PREFIX."
        return 0
    fi

    local src="$BUILD_DIR/ncurses-${NCURSES_VERSION}"
    [[ -d "$src" ]] || download_and_extract "$NCURSES_URL"

    log "Building ncurses ${NCURSES_VERSION}..."
    (
        cd "$src"
        ./configure \
            --prefix="$PREFIX" \
            --with-shared \
            --without-debug \
            --without-ada \
            --without-tests
        make -j"$JOBS"
        make install
    )

    log_success "ncurses installed → $PREFIX."
}

# --- zsh ----------------------------------------------------------------------

build_zsh() {
    if [[ -x "$PREFIX/bin/zsh" ]]; then
        local ver
        ver="$("$PREFIX/bin/zsh" --version 2>/dev/null | awk '{print $2}')"
        log_warning "zsh ${ver} already present at $PREFIX/bin/zsh."
        confirm "Rebuild zsh ${ZSH_VERSION}?" "N" || return 0
    fi

    local src="$BUILD_DIR/zsh-${ZSH_VERSION}"
    [[ -d "$src" ]] || download_and_extract "$ZSH_URL"

    log "Building zsh ${ZSH_VERSION}..."
    (
        cd "$src"
        # Point configure at our locally-built ncurses (harmless if system one is used).
        CPPFLAGS="-I$PREFIX/include" \
        LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" \
        ./configure \
            --prefix="$PREFIX" \
            --enable-multibyte \
            --with-tcsetpgrp
        make -j"$JOBS"
        make install
    )

    log_success "zsh ${ZSH_VERSION} installed → $PREFIX/bin/zsh."
}

# --- Shell wiring -------------------------------------------------------------

configure_shell() {
    # 1) Ensure $PREFIX/bin is on PATH in .bashrc/.zshrc.
    add_block_to_shell_configs \
        "export PATH=\"$PREFIX/bin:\$PATH\"" \
        "$PREFIX/bin"

    # 2) Auto-launch this zsh for interactive bash sessions (chsh needs root).
    #    Skip if any zsh exec block already exists — including the one written
    #    by install_zsh.sh (which hardcodes /usr/bin/zsh).
    local bashrc="$HOME/.bashrc"
    touch "$bashrc"

    if grep -Eq '^[[:space:]]*exec[[:space:]]+.*/zsh' "$bashrc"; then
        log "Existing zsh auto-launch block found in $bashrc — leaving it alone."
        return 0
    fi

    cat >> "$bashrc" <<EOF

# Auto-launch user-built zsh for interactive shells (source build, no sudo)
if [ -n "\$PS1" ] && [ -z "\$ZSH_VERSION" ] && [ -x "$PREFIX/bin/zsh" ]; then
  exec "$PREFIX/bin/zsh"
fi
EOF
    log "Added zsh auto-launch to $bashrc."
}

# --- Main ---------------------------------------------------------------------

main() {
    log "zsh source build — version=${ZSH_VERSION}"
    check_environment
    check_build_tools

    mkdir -p "$PREFIX" "$BUILD_DIR"

    if system_ncurses_available; then
        log_success "System ncurses headers detected — skipping ncurses build."
    else
        log_warning "No system ncurses headers — building ncurses ${NCURSES_VERSION} into $PREFIX."
        build_ncurses
    fi

    build_zsh
    configure_shell

    log_success "Done. Start a new shell, or run: exec $PREFIX/bin/zsh"
    log "Next: bash scripts/install_zsh.sh   # Oh My Zsh + plugins (uses whichever zsh is on PATH)"
}

main "$@"
