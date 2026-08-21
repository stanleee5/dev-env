#!/bin/bash
# ==============================================================================
# Python Package Installation Script
#
# This script installs Python packages from requirements.txt and configures
# useful shell aliases for Python development.
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

readonly REQUIREMENTS_FILE="$CONFIG_DIR/requirements.txt"

# --- Helper Functions ---

get_install_command() {
    if command_exists pip3; then
        echo "pip3"
    elif command_exists pip; then
        echo "pip"
    else
        log_error "pip is not installed. Please install Python and pip first."
        return 1
    fi
}

upgrade_pip() {
    local cmd="$1"
    log "Upgrading pip..."
    if ! "$cmd" install --no-cache-dir -U pip setuptools wheel; then
        log_error "Failed to upgrade pip"
        return 1
    fi
    log_success "pip upgraded successfully"
}

install_packages() {
    local cmd="$1"
    local requirements_file="$2"

    if [[ ! -f "$requirements_file" ]]; then
        log_warning "Requirements file not found at $requirements_file"
        log "Skipping package installation."
        return 0
    fi

    log "Installing packages from $requirements_file..."
    if ! "$cmd" install --no-cache-dir -r "$requirements_file"; then
        log_error "Failed to install packages via pip"
        return 1
    fi
    log_success "All packages installed successfully"
}

# Configure shell aliases for Python development
configure_shell_aliases() {
    log "Configuring shell aliases..."
    add_block_to_shell_configs 'alias python="python3"'
    add_block_to_shell_configs 'alias pinstall="pip install --no-cache-dir"'
    add_block_to_shell_configs $'py() {\n  isort "$1"\n  black "$1"\n}' 'py() {'
    log_success "Shell configuration updated"
}

# --- Main Execution ---

main() {
    log "Starting Python package installation..."

    local cmd
    cmd=$(get_install_command) || exit 1
    log "Using installer: $cmd"

    upgrade_pip "$cmd" || exit 1

    # Install packages
    install_packages "$cmd" "$REQUIREMENTS_FILE" || exit 1

    # Configure shell aliases
    configure_shell_aliases

    log_success "Python setup completed successfully!"
}

# Run the main function
main "$@"
