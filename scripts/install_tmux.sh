#!/bin/bash
# ==============================================================================
# Tmux Setup Script
#
# This script installs and configures Tmux with a custom configuration.
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

if is_docker; then
    readonly TMUX_CONFIG="/workspace/.tmux.conf"
    readonly TMUX_PLUGIN_DIR="/workspace/.config/tmux/plugins"
else
    readonly TMUX_CONFIG="$(get_user_home)/.tmux.conf"
    readonly TMUX_PLUGIN_DIR="${XDG_CONFIG_HOME:-$(get_user_home)/.config}/tmux/plugins"
fi
readonly CUSTOM_TMUX_CONFIG="$CONFIG_DIR/tmux.conf"

# Plugins to pre-install. Keep in sync with the `@plugin` lines in
# config/tmux.conf. Format: "<plugin-dir-name>:<git-url>".
readonly TMUX_PLUGINS=(
    "tpm:https://github.com/tmux-plugins/tpm.git"
    "tmux-powerkit:https://github.com/fabioluciano/tmux-powerkit.git"
)

setup_tmux() {
    log "Configuring Tmux..."
    
    local config_dir
    config_dir=$(dirname "$TMUX_CONFIG")
    mkdir -p "$config_dir"
    
    # Resolve the zsh binary currently on PATH so source-installs
    # (e.g. ~/.local/bin/zsh) are honored instead of hard-coding /usr/bin/zsh.
    # tmux's default-shell must be an absolute path, so we bake it in here.
    local zsh_bin
    zsh_bin=$(command -v zsh || true)
    if [[ -z "$zsh_bin" ]]; then
        log_warning "zsh not found on PATH; tmux default-shell will fall back to /bin/sh"
        zsh_bin="/bin/sh"
    else
        log "Using zsh binary for tmux default-shell: $zsh_bin"
    fi

    # Only copy if source and destination are different files
    if [[ "$CUSTOM_TMUX_CONFIG" != "$TMUX_CONFIG" ]]; then
        cp -f "$CUSTOM_TMUX_CONFIG" "$TMUX_CONFIG"
    fi
    # Substitute placeholders with their resolved absolute paths.
    sed -i \
        -e "s|@@ZSH_BIN@@|$zsh_bin|g" \
        -e "s|@@TMUX_PLUGIN_PATH@@|$TMUX_PLUGIN_DIR|g" \
        "$TMUX_CONFIG"
    chmod 644 "$TMUX_CONFIG"
    
    if is_docker; then
        chown root:root "$TMUX_CONFIG" 2>/dev/null || true
        run_privileged ln -sf "$TMUX_CONFIG" "/etc/tmux.conf"
        log "Linked tmux config to /etc/tmux.conf"
    else
        local user
        user=$(get_user)
        run_privileged chown "$user:$user" "$TMUX_CONFIG" 2>/dev/null || true
        local user_home_tmux
        user_home_tmux="$(get_user_home)/.tmux.conf"
        if [[ "$user_home_tmux" != "$TMUX_CONFIG" ]]; then
            ln -sf "$TMUX_CONFIG" "$user_home_tmux"
        fi
    fi
    
    log_success "Tmux configuration applied."
}

setup_tmux_plugins() {
    log "Installing tmux plugins into $TMUX_PLUGIN_DIR..."
    mkdir -p "$TMUX_PLUGIN_DIR"

    for entry in "${TMUX_PLUGINS[@]}"; do
        local name="${entry%%:*}"
        local url="${entry#*:}"
        local dest="$TMUX_PLUGIN_DIR/$name"

        if [[ -d "$dest/.git" ]]; then
            log "Plugin $name already present, pulling latest..."
            # Discard the patch below so it cannot block the fast-forward.
            git -C "$dest" checkout --quiet -- . 2>/dev/null || true
            git -C "$dest" pull --ff-only --quiet || \
                log_warning "Failed to update $name; keeping existing checkout"
        else
            log "Cloning $name from $url"
            git clone --depth 1 --quiet "$url" "$dest" || {
                log_error "Failed to clone $name"
                return 1
            }
        fi

        # tmux-powerkit's TPM entry point hard-gates on Bash 5.2+, but that is
        # its dev-tooling threshold -- the README asks for 5.0+ and the runtime
        # only branches at 5.1. Ubuntu ships 5.1 (22.04) or 5.0 (20.04), so the
        # gate makes the entry point exit 1, which makes `run tpm` fail, which
        # aborts TPM before it sources ANY plugin: the whole status bar silently
        # reverts to tmux defaults. Lower it to the documented 5.0 requirement.
        if [[ "$name" == "tmux-powerkit" ]]; then
            sed -i 's/BASH_VERSINFO\[1\] < 2/BASH_VERSINFO[1] < 0/' \
                "$dest/tmux-powerkit.tmux"
        fi
    done

    if ! is_docker; then
        local user
        user=$(get_user)
        run_privileged chown -R "$user:$user" "$TMUX_PLUGIN_DIR" 2>/dev/null || true
    fi

    log_success "Tmux plugins installed."
}

main() {
    log "Starting Tmux setup..."
    setup_tmux
    setup_tmux_plugins
    log_success "Tmux setup completed!"
}

main "$@"
