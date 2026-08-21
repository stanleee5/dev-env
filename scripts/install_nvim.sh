#!/bin/bash
# ==============================================================================
# Neovim Setup Script (Docker + Local)
#
# Installs Neovim binary, copies config, sets up plugins via lazy.nvim,
# and installs the pyright language server (native LSP).
# Node.js: installed in Dockerfile (Docker) or via NVM (local).
#
# Usage: ./install_nvim.sh [nvim_version]
# Default version: v0.11.3
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# --- Constants ----------------------------------------------------------------

readonly NVM_VERSION="v0.40.0"
readonly NODE_VERSION="24"
readonly NVIM_VERSION="${1:-v0.11.3}"

readonly BASE_DIR="$(get_base_dir)"
readonly NVIM_INSTALL_DIR="$BASE_DIR/nvim"
export NVM_DIR="$BASE_DIR/.nvm"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$BASE_DIR/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$BASE_DIR/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$BASE_DIR/.cache}"

# --- Environment --------------------------------------------------------------

setup_environment() {
    if ! is_docker; then return 0; fi

    log "Configuring Docker environment..."
    export DEBIAN_FRONTEND=noninteractive
    export TERM=xterm-256color

    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

    if [[ "$BASE_DIR" != "$HOME" ]]; then
        [[ ! -e "$HOME/.config" ]] && ln -s "$XDG_CONFIG_HOME" "$HOME/.config"
        [[ ! -e "$HOME/.local" ]]  && ln -s "$XDG_DATA_HOME"   "$HOME/.local"
    fi

    chmod -R 755 "$BASE_DIR" 2>/dev/null || true
}

check_dependencies() {
    local missing=()
    for cmd in curl tar git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        if is_docker; then
            apt-get update -qq && apt-get install -y -qq "${missing[@]}"
        else
            log_error "Missing dependencies: ${missing[*]}"
            return 1
        fi
    fi
    log_success "Dependencies OK."
}

# --- Node.js ------------------------------------------------------------------

install_node() {
    # Docker: Node.js is pre-installed in Dockerfile
    if is_docker; then
        if command -v node &>/dev/null; then
            log_success "Node.js $(node -v) already available."
            return 0
        fi
        log_error "Node.js not found (should be installed in Dockerfile)."
        return 1
    fi

    # Local: install via NVM
    if command -v node &>/dev/null; then
        log_warning "Node.js $(node -v) already installed."
        confirm "Reinstall via NVM?" "N" || return 0
    fi

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        log "Installing NVM..."
        mkdir -p "$NVM_DIR"
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
    fi

    add_block_to_shell_configs "$(cat <<EOF
# NVM
export NVM_DIR="$NVM_DIR"
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
EOF
)" "NVM_DIR"

    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install "$NODE_VERSION"
    nvm use "$NODE_VERSION"
    nvm alias default "$NODE_VERSION"

    log_success "Node.js $(node -v) installed."
}

# --- Neovim binary ------------------------------------------------------------

install_neovim() {
    if ! is_docker && command -v nvim &>/dev/null; then
        log_warning "Neovim $(nvim --version | head -1 | cut -d' ' -f2) already installed."
        confirm "Reinstall $NVIM_VERSION?" "N" || return 0
    fi

    # Determine archive filename (changed in v0.11+)
    local minor
    minor=$(echo "$NVIM_VERSION" | sed 's/^v0\.//' | cut -d'.' -f1)
    local filename="nvim-linux-x86_64.tar.gz"
    [[ "$minor" -le 10 ]] && filename="nvim-linux64.tar.gz"

    local url="https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/$filename"
    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" EXIT

    log "Downloading Neovim $NVIM_VERSION..."
    curl -fL -o "$tmp/$filename" "$url"

    log "Installing to $NVIM_INSTALL_DIR..."
    rm -rf "$NVIM_INSTALL_DIR"
    mkdir -p "$NVIM_INSTALL_DIR"
    tar -xzf "$tmp/$filename" -C "$NVIM_INSTALL_DIR" --strip-components=1

    rm -rf "$tmp"
    trap - EXIT

    # Make nvim available system-wide via PATH + alias.
    export PATH="$NVIM_INSTALL_DIR/bin:$PATH"
    add_block_to_shell_configs "export PATH=\"$NVIM_INSTALL_DIR/bin:\$PATH\""
    add_block_to_shell_configs "alias vim=nvim"

    log_success "Neovim $NVIM_VERSION installed."
}

# --- Config -------------------------------------------------------------------

copy_config() {
    local src="$CONFIG_DIR/nvim"
    local dst="$XDG_CONFIG_HOME/nvim"

    if [[ ! -f "$src/init.lua" ]]; then
        log_error "init.lua not found in $src"
        return 1
    fi

    log "Copying config to $dst..."
    mkdir -p "$dst"
    # "/." — .luarc.json 같은 dotfile까지 포함해 복사
    cp -r "$src"/. "$dst/"
    log_success "Config copied."
}

# --- Plugins ------------------------------------------------------------------

install_plugins() {
    for cmd in node git nvim; do
        command -v "$cmd" &>/dev/null || { log_error "$cmd required but not found."; return 1; }
    done

    # Load NVM for local environments
    ! is_docker && [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    local config_file="$XDG_CONFIG_HOME/nvim/init.lua"
    [[ -f "$config_file" ]] || { log_error "Config not found: $config_file"; return 1; }

    # 1) lazy.nvim: bootstrap + sync (generates lazy-lock.json to pin versions)
    log "Syncing plugins via lazy.nvim..."
    nvim --headless "+Lazy! sync" +qa 2>&1 | tee -a "$LOG_FILE" || \
        log_warning "lazy.nvim sync encountered issues."

    # 2) blink.cmp: wait for the prebuilt fuzzy binary download so it gets
    #    baked into the image (falls back to the Lua matcher if unavailable)
    log "Waiting for blink.cmp fuzzy library download..."
    nvim --headless "+lua (function() local p = vim.fn.stdpath('data') .. '/lazy/blink.cmp/target/release/'; vim.wait(60000, function() return vim.uv.fs_stat(p .. 'libblink_cmp_fuzzy.so') ~= nil or vim.uv.fs_stat(p .. 'libblink_cmp_fuzzy.dylib') ~= nil end, 1000) end)()" +qa 2>&1 | tee -a "$LOG_FILE" || true
    if ls "$XDG_DATA_HOME/nvim/lazy/blink.cmp/target/release/"libblink_cmp_fuzzy.* &>/dev/null; then
        log_success "blink.cmp fuzzy binary ready."
    else
        log_warning "blink.cmp fuzzy binary not downloaded; will use Lua fallback matcher."
    fi

    log_success "Plugins installed."
}

# --- Language servers ---------------------------------------------------------
# ruff는 config/requirements.txt(pip)로 설치된다. 여기서는 나머지를 담당한다.

readonly LUALS_VERSION="3.19.1"

install_language_servers() {
    # pyright + bash-language-server: npm으로 진짜 바이너리를 PATH에 설치
    # (pip pyright 래퍼처럼 첫 실행 때 런타임 다운로드하는 일이 없다)
    local npm_servers=()
    command -v pyright-langserver &>/dev/null || npm_servers+=(pyright)
    command -v bash-language-server &>/dev/null || npm_servers+=(bash-language-server)
    if [[ ${#npm_servers[@]} -gt 0 ]]; then
        log "Installing npm language servers: ${npm_servers[*]}..."
        npm install -g "${npm_servers[@]}" 2>&1 | tee -a "$LOG_FILE" || \
            log_warning "npm language server installation encountered issues."
    else
        log_success "pyright-langserver and bash-language-server already available."
    fi

    # lua-language-server: GitHub 릴리스 tarball (linux x64 전용; macOS는 brew 사용)
    if command -v lua-language-server &>/dev/null; then
        log_success "lua-language-server already available."
        return 0
    fi
    if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
        log_warning "lua-language-server: unsupported platform ($(uname -sm)); install manually (e.g. brew install lua-language-server)."
        return 0
    fi

    local luals_dir
    if is_docker; then
        # /workspace 볼륨 마운트에 가려지지 않는 위치에 설치
        luals_dir="/usr/local/lua-language-server"
    else
        luals_dir="$BASE_DIR/.local/opt/lua-language-server"
    fi

    local url="https://github.com/LuaLS/lua-language-server/releases/download/$LUALS_VERSION/lua-language-server-$LUALS_VERSION-linux-x64.tar.gz"
    local tmp
    tmp=$(mktemp -d)
    log "Downloading lua-language-server $LUALS_VERSION..."
    if curl -fL -o "$tmp/luals.tar.gz" "$url" 2>&1 | tee -a "$LOG_FILE"; then
        run_privileged mkdir -p "$luals_dir"
        run_privileged tar -xzf "$tmp/luals.tar.gz" -C "$luals_dir"
        if is_docker; then
            ln -sf "$luals_dir/bin/lua-language-server" /usr/local/bin/lua-language-server
        else
            add_block_to_shell_configs "export PATH=\"$luals_dir/bin:\$PATH\""
        fi
        log_success "lua-language-server $LUALS_VERSION installed."
    else
        log_warning "lua-language-server download failed; skipping."
    fi
    rm -rf "$tmp"
}

# --- Main ---------------------------------------------------------------------

main() {
    log "Neovim setup — env=$(is_docker && echo Docker || echo Local), version=$NVIM_VERSION"

    setup_environment
    check_dependencies
    install_node
    copy_config          # config BEFORE binary (binary installs to $BASE_DIR/nvim)
    install_neovim
    install_plugins
    install_language_servers

    log_success "Neovim setup complete!"
    if is_docker; then
        log "Ready to use: nvim or vim"
    else
        log "Restart your shell or source ~/.bashrc / ~/.zshrc"
    fi
}

main "$@"
