#!/bin/bash
# ==============================================================================
# Zsh Setup Script
#
# This script installs and configures Zsh with Oh My Zsh framework and
# custom plugins. It is Docker-aware and works in both local and container
# environments.
#
# Features:
#   - Installs Zsh package
#   - Installs Oh My Zsh framework
#   - Configures custom theme (adben)
#   - Installs zsh-autosuggestions and zsh-syntax-highlighting plugins
#   - Configures Zsh as default shell for interactive sessions
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# Get Docker-aware base directory (returns /workspace in Docker, $HOME locally)
# But respect ZDOTDIR if already set (e.g., in Dockerfile)
if [[ -n "${ZDOTDIR:-}" ]]; then
    readonly BASE_DIR="$ZDOTDIR"
else
    readonly BASE_DIR="$(get_base_dir)"
fi

# Zsh configuration
readonly ZSH_THEME="adben"
readonly CUSTOM_PLUGINS=(zsh-autosuggestions zsh-syntax-highlighting)

# Installation paths (Docker-aware)
readonly OH_MY_ZSH_DIR="$BASE_DIR/.oh-my-zsh"
readonly ZSH_CONFIG="$BASE_DIR/.zshrc"
readonly ZSH_ENV_CONFIG="$BASE_DIR/.zshenv"
readonly BASH_CONFIG="$BASE_DIR/.bashrc"

# --- Helper Functions ---

# Check if Zsh is installed and display version
check_zsh_version() {
    if command -v zsh &> /dev/null; then
        local version
        version=$(zsh --version 2>/dev/null | head -n1)
        log "Found Zsh: $version"
        return 0
    else
        log "Zsh not found, will install."
        return 1
    fi
}

# --- Installation Functions ---

# Verify Zsh installation
verify_zsh_installation() {
    # Verify installation
    if ! command -v zsh &> /dev/null; then
        log_error "Zsh installation verification failed"
        return 1
    fi
    
    check_zsh_version
    log_success "Zsh installed successfully"
}

# Install Oh My Zsh framework
install_oh_my_zsh() {
    log "Installing Oh My Zsh framework..."
    
    # Check if already installed
    if [[ -d "$OH_MY_ZSH_DIR" ]]; then
        log_warning "Oh My Zsh is already installed at $OH_MY_ZSH_DIR"
        if ! is_docker && ! confirm "Reinstall Oh My Zsh?" "N"; then
            log "Skipping Oh My Zsh installation."
            return 0
        fi
        log "Removing existing Oh My Zsh installation..."
        rm -rf "$OH_MY_ZSH_DIR"
    fi
    
    # Remove existing .zshrc if present (we'll configure it properly after installation)
    if [[ -f "$ZSH_CONFIG" ]]; then
        log "Backing up existing .zshrc..."
        mv "$ZSH_CONFIG" "${ZSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" || true
    fi
    
    log "Installing Oh My Zsh to $OH_MY_ZSH_DIR..."
    
    # Download installer script
    local install_script
    install_script=$(mktemp)
    trap "rm -f '$install_script'" EXIT INT TERM
    
    if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$install_script"; then
        log_error "Failed to download Oh My Zsh installer"
        return 1
    fi
    
    # Run installer with proper environment for unattended installation
    if ! env \
        RUNZSH=no \
        CHSH=no \
        KEEP_ZSHRC=no \
        ZSH="$OH_MY_ZSH_DIR" \
        HOME="$BASE_DIR" \
        ZDOTDIR="$BASE_DIR" \
        sh "$install_script"; then
        log_error "Oh My Zsh installation failed"
        return 1
    fi
    
    # Verify .zshrc was created
    if [[ ! -f "$ZSH_CONFIG" ]]; then
        log_error ".zshrc was not created by Oh My Zsh installer"
        return 1
    fi
    
    log_success "Oh My Zsh installed successfully"
}

# Install a custom Zsh plugin from GitHub
install_zsh_plugin() {
    local plugin_name="$1"
    local plugin_url="https://github.com/zsh-users/$plugin_name"
    local plugin_dir="$OH_MY_ZSH_DIR/custom/plugins/$plugin_name"
    
    if [[ -d "$plugin_dir" ]]; then
        log "$plugin_name plugin is already installed"
        return 0
    fi
    
    log "Installing $plugin_name plugin..."
    if git clone "$plugin_url" "$plugin_dir" 2>/dev/null; then
        log_success "$plugin_name plugin installed"
        return 0
    fi
    
    log_error "Failed to clone $plugin_name"
    return 1
}

# Configure Zsh theme in .zshrc
configure_zsh_theme() {
    log "Configuring Zsh theme to '$ZSH_THEME'..."
    
    # Set or update theme
    if grep -q "^ZSH_THEME=" "$ZSH_CONFIG"; then
        sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"$ZSH_THEME\"/" "$ZSH_CONFIG"
        log "Updated ZSH_THEME to '$ZSH_THEME'"
    else
        # Insert after ZSH= line if it exists, otherwise at the beginning
        if grep -q "^ZSH=" "$ZSH_CONFIG"; then
            local insert_line
            insert_line=$(grep -n "^ZSH=" "$ZSH_CONFIG" | head -n1 | cut -d: -f1)
            sed -i "${insert_line}a ZSH_THEME=\"$ZSH_THEME\"" "$ZSH_CONFIG"
        else
            sed -i "1i ZSH_THEME=\"$ZSH_THEME\"" "$ZSH_CONFIG"
        fi
        log "Added ZSH_THEME='$ZSH_THEME'"
    fi
    
    # Verify the theme was set correctly
    if grep -q "^ZSH_THEME=\"$ZSH_THEME\"" "$ZSH_CONFIG"; then
        log_success "Theme configured: $ZSH_THEME"
    else
        log_warning "Theme configuration may not have been applied correctly"
    fi
}

# Configure plugins list in .zshrc
configure_zsh_plugins() {
    log "Configuring Zsh plugins..."

    if ! grep -q "^plugins=" "$ZSH_CONFIG"; then
        echo "plugins=(git ${CUSTOM_PLUGINS[*]})" >> "$ZSH_CONFIG"
        log_success "Plugins configured"
        return 0
    fi

    for plugin in "${CUSTOM_PLUGINS[@]}"; do
        if ! grep "^plugins=" "$ZSH_CONFIG" | grep -q "$plugin"; then
            sed -i "s/^plugins=(\(.*\))/plugins=(\1 $plugin)/" "$ZSH_CONFIG"
        fi
    done
    log_success "Plugins configured"
}

# Append the `slack` shell function to .zshrc (idempotent)
configure_slack_function() {
    log "Adding 'slack' function to $ZSH_CONFIG..."

    if grep -q "^function slack()" "$ZSH_CONFIG" 2>/dev/null; then
        log "'slack' function already present in $ZSH_CONFIG"
        return 0
    fi

    cat >> "$ZSH_CONFIG" <<'EOF'

function slack() {
    local message=$1
    local webhook_url=""
    local host_name=$(hostname)
    local curr_time=$(date "+%Y-%m-%d %H:%M:%S")

    # 가독성을 위해 호스트와 시간을 인용구(>)로 처리했습니다.
    local payload=$(cat <<PAYLOAD
{
    "text": "*$message*\n>*Server:* $host_name\n>*Time:* $curr_time"
}
PAYLOAD
)
    curl -s -X POST -H 'Content-type: application/json' --data "$payload" "$webhook_url" > /dev/null
}
EOF
    log_success "'slack' function appended to $ZSH_CONFIG"
}

# Write a .zshenv that restores zsh's bundled function dirs on fpath.
# Some environments (e.g. Lmod) export a polluted FPATH that omits the zsh
# install's own function directory, which breaks compinit/add-zsh-hook/etc.
configure_zshenv_fpath_guard() {
    log "Writing fpath guard to $ZSH_ENV_CONFIG..."

    local marker="# [dice-setup] fpath guard"

    if [[ -f "$ZSH_ENV_CONFIG" ]] && grep -qF "$marker" "$ZSH_ENV_CONFIG"; then
        log "fpath guard already present in $ZSH_ENV_CONFIG"
        return 0
    fi

    cat >> "$ZSH_ENV_CONFIG" <<'EOF'

# [dice-setup] fpath guard
# Restore zsh's bundled function directory on fpath. Environments like Lmod
# export a stale FPATH into the parent shell; zsh would otherwise inherit it
# and lose access to compinit, add-zsh-hook, is-at-least, colors, etc.
() {
  local zsh_bin="${commands[zsh]:-${0:A}}"
  local share="${zsh_bin:h:h}/share/zsh/${ZSH_VERSION}"
  if [[ -d "$share/functions" ]]; then
    typeset -gU fpath
    fpath=( "$share/functions" "$share"/functions/*(N/) $fpath )
  fi
}
EOF
    log_success "fpath guard written to $ZSH_ENV_CONFIG"
}

# Setup Zsh plugins and configuration
setup_zsh_plugins() {
    # Verify .zshrc exists (should have been created by Oh My Zsh)
    if [[ ! -f "$ZSH_CONFIG" ]]; then
        log_error ".zshrc not found at $ZSH_CONFIG. Oh My Zsh installation may have failed."
        return 1
    fi
    
    # Install custom plugins
    for plugin in "${CUSTOM_PLUGINS[@]}"; do
        install_zsh_plugin "$plugin" || return 1
    done
    
    # Configure theme and plugins
    configure_zsh_theme || return 1
    configure_zsh_plugins || return 1
    configure_zshenv_fpath_guard || return 1
    configure_slack_function || return 1
    
    # Ensure proper file ownership and permissions
    local user
    user=$(get_user)
    run_privileged chown -R "$user:$user" "$OH_MY_ZSH_DIR" "$ZSH_CONFIG" "$ZSH_ENV_CONFIG" 2>/dev/null || true
    run_privileged chmod -R g-w,o-w "$OH_MY_ZSH_DIR" 2>/dev/null || true

    log_success "Zsh plugins and theme configured successfully"
}

# Configure Zsh to launch automatically for interactive shells
ensure_zsh_is_default() {
    log "Configuring Zsh as the default interactive shell..."

    # Resolve the zsh binary currently on PATH so source-installs
    # (e.g. ~/.local/bin/zsh) are honored instead of hard-coding /usr/bin/zsh.
    local zsh_bin
    zsh_bin=$(command -v zsh || true)
    if [[ -z "$zsh_bin" ]]; then
        log_error "zsh not found on PATH; cannot configure auto-launch"
        return 1
    fi
    log "Using zsh binary: $zsh_bin"

    # Create .bashrc if it doesn't exist
    touch "$BASH_CONFIG"

    # Check if auto-launch logic already exists (any prior exec zsh line).
    # Matches lines like:  exec "/path/to/zsh"  /  exec zsh  /  exec /usr/bin/zsh
    if grep -qE '^[[:space:]]*exec[[:space:]]+["'\'']?[^[:space:]"'\'']*zsh' "$BASH_CONFIG"; then
        log "Zsh auto-launch configuration already present in $BASH_CONFIG"
        return 0
    fi

    # Add logic to launch Zsh for interactive shells
    # NOTE: FPATH is unset before exec because environments like Lmod export
    # a stale FPATH into bash; zsh would inherit it and lose its compile-time
    # default fpath, breaking compinit/add-zsh-hook/etc.
    local zsh_launch_logic="
# Auto-launch Zsh for interactive shells
if [ -n \"\$PS1\" ] && [ -z \"\$ZSH_VERSION\" ] && [ -x \"$zsh_bin\" ]; then
  # Set ZDOTDIR to Docker-aware location if needed
  if [ -d \"$BASE_DIR/.oh-my-zsh\" ]; then
    export ZDOTDIR=\"$BASE_DIR\"
  fi
  unset FPATH
  exec \"$zsh_bin\"
fi
"
    
    log "Adding Zsh auto-launch logic to $BASH_CONFIG..."
    echo "$zsh_launch_logic" >> "$BASH_CONFIG"
    
    log_success "Zsh will now be the default for new interactive terminal sessions"
}

# --- Main Execution ---

main() {
    log "Starting Zsh setup..."
    log "Environment: $(if is_docker; then echo "Docker"; else echo "Local"; fi)"
    log "Base directory: $BASE_DIR"
    log "Zsh config: $ZSH_CONFIG"
    
    # Ensure base directory exists
    if [[ ! -d "$BASE_DIR" ]]; then
        log "Creating base directory: $BASE_DIR"
        mkdir -p "$BASE_DIR" || {
            log_error "Failed to create base directory: $BASE_DIR"
            return 1
        }
    fi
    
    # Verify Zsh installation
    verify_zsh_installation || exit 1
    
    # Install and configure Zsh
    install_oh_my_zsh || exit 1
    setup_zsh_plugins || exit 1
    ensure_zsh_is_default || exit 1
    
    log_success "Zsh setup completed successfully!"
    log "To apply changes, start a new terminal session or run: exec zsh"
}

# Run main function
main "$@"
