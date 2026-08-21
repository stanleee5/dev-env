#!/bin/bash
# ==============================================================================
# Bash Utilities Library
#
# This file provides common utility functions for setup scripts including:
#   - Logging functions (log, log_success, log_warning, log_error)
#   - Environment detection (Docker, root, sudo, user)
#   - Shell config management (add_block_to_shell_configs)
#   - Privileged execution helper (run_privileged)
#   - User interaction (confirm prompts)
#
# This file is designed to be sourced by other scripts.
# ==============================================================================

# Prevent multiple sourcing
if [[ "${BASH_UTILS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly BASH_UTILS_LOADED=true

# Error handling (applied to all scripts that source this file)
set -euo pipefail

# Configuration
LOG_FILE="${LOG_FILE:-/tmp/setup.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
# Built as root but usually run as a non-root uid, so the build's root-owned log
# makes tee fail -- and every log function pipes into tee under `set -e`, which
# kills re-runs on a live machine at the first log line. Note `2>/dev/null` must
# precede the append, or the shell reports the failure before stderr is silenced.
: 2>/dev/null >>"$LOG_FILE" || LOG_FILE="/tmp/setup-$(id -u).log"
readonly LOG_FILE

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Environment Detection
detect_environment() {
    if [[ "${DOCKER_BUILD:-}" == "true" ]]; then
        echo "docker"
    elif [[ "$(id -u)" -eq 0 ]]; then
        echo "root"
    elif command -v sudo >/dev/null 2>&1; then
        echo "sudo"
    else
        echo "user"
    fi
}

# Check if running in Docker
is_docker() {
    [[ "$(detect_environment)" == "docker" ]]
}

# Get Docker-aware base directory
get_base_dir() {
    if is_docker; then
        echo "/workspace"
    else
        echo "$HOME"
    fi
}

# Check if running in non-interactive environment
is_non_interactive() {
    [[ "${CI:-false}" == "true" ]] || \
    is_docker || \
    [[ "${DEBIAN_FRONTEND:-}" == "noninteractive" ]] || \
    [[ ! -t 0 ]]
}

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗ $*${NC}" | tee -a "$LOG_FILE"
}

# ERR trap (defined after logging functions)
trap 'log_error "Script failed at line ${LINENO}"' ERR

# Directory constants (repo layout: setups/{scripts,config}/)
readonly SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETUP_DIR="$(dirname "$SCRIPTS_DIR")"
readonly CONFIG_DIR="$SETUP_DIR/config"

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirm with user - auto-accepts in non-interactive mode
confirm() {
    local message="$1"
    local default="${2:-N}"
    local prompt="(y/N)"
    [[ "$default" == "Y" ]] && prompt="(Y/n)"
    
    # Auto-accept in non-interactive environments
    if is_non_interactive; then
        if [[ "$default" == "Y" ]]; then
            log "$message $prompt: Y (auto-accepted)"
            return 0
        else
            log "$message $prompt: N (auto-declined)"
            return 1
        fi
    fi
    
    # Interactive mode
    read -p "$message $prompt: " -n 1 -r
    echo
    if [[ "$default" == "Y" ]]; then
        [[ ! ${REPLY:-} =~ ^[Nn]$ ]]
    else
        [[ ${REPLY:-} =~ ^[Yy]$ ]]
    fi
}

# Get actual user
get_user() {
    echo "${SUDO_USER:-${USER:-$(whoami 2>/dev/null || echo root)}}"
}

# Get user home directory - Docker-aware
get_user_home() {
    local user="${1:-$(get_user)}"
    if is_docker; then
        echo "/workspace"
    elif [[ "$user" == "root" ]]; then
        echo "/root"
    else
        echo "/home/$user"
    fi
}

# Get shell config files - Docker-aware
get_shell_configs() {
    local base_dir
    base_dir=$(get_base_dir)
    local configs_found=()
    
    # Check for .zshrc first (preferred)
    if [[ -f "$base_dir/.zshrc" ]]; then
        configs_found+=("$base_dir/.zshrc")
    fi
    
    # Check for .bashrc
    if [[ -f "$base_dir/.bashrc" ]]; then
        configs_found+=("$base_dir/.bashrc")
    fi
    
    # Create .zshrc as fallback if no configs found
    if [[ ${#configs_found[@]} -eq 0 ]]; then
        touch "$base_dir/.zshrc" 2>/dev/null || true
        configs_found=("$base_dir/.zshrc")
    fi
    
    printf '%s\n' "${configs_found[@]}"
}

# Add block to shell configs (handles both single lines and multi-line blocks)
add_block_to_shell_configs() {
    local block="$1"
    local check_pattern="${2:-$block}"  # Use block itself as pattern if not provided
    local shell_configs
    
    readarray -t shell_configs < <(get_shell_configs)
    for config_file in "${shell_configs[@]}"; do
        if ! grep -qF -- "$check_pattern" "$config_file"; then
            log "Adding configuration to $config_file"
            echo "$block" >> "$config_file"
        else
            log "Configuration already exists in $config_file"
        fi
    done
}

# Execute privileged commands
run_privileged() {
    local cmd="$*"
    local env
    env=$(detect_environment)
    
    case "$env" in
        "docker"|"root")
            bash -c "$cmd"
            ;;
        "sudo")
            if sudo -n true 2>/dev/null; then
                sudo bash -c "$cmd"
            else
                if is_non_interactive; then
                    log_error "Cannot prompt for sudo password in non-interactive mode"
                    return 1
                fi
                echo "Administrator privileges required for: $cmd"
                sudo bash -c "$cmd"
            fi
            ;;
        "user")
            log_error "No sufficient privileges to execute: $cmd"
            log_error "Please run as root or install sudo"
            return 1
            ;;
    esac
}

