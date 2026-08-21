#!/bin/bash
# ==============================================================================
# Claude Code Setup Script
#
# This script installs and configures Claude Code with statusline.
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

if is_docker; then
    readonly CLAUDE_DIR="/workspace/.claude"
else
    readonly CLAUDE_DIR="$(get_user_home)/.claude"
fi

install_claude_code() {
    log "Installing Claude Code..."

    if command -v claude >/dev/null 2>&1; then
        log "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown')"
    else
        if command -v npm >/dev/null 2>&1; then
            log "Installing via npm..."
            npm install -g @anthropic-ai/claude-code
        else
            log "npm not found, trying native installer..."
            curl -fsSL https://claude.ai/install.sh | bash
        fi
        log_success "Claude Code installed."
    fi
}

setup_statusline() {
    log "Configuring Claude Code statusline..."

    local scripts_dir="${CLAUDE_DIR}/scripts"
    mkdir -p "$scripts_dir"

    cp -f "$CONFIG_DIR/claude/statusline.sh" "$scripts_dir/statusline.sh"
    chmod +x "$scripts_dir/statusline.sh"

    # Register statusline in Claude Code settings.json
    local settings_file="${CLAUDE_DIR}/settings.json"
    local statusline_cmd="${scripts_dir}/statusline.sh"

    if [[ -f "$settings_file" ]]; then
        # Merge statusline setting into existing settings.json
        local tmp_file="${settings_file}.tmp"
        jq --arg cmd "$statusline_cmd" \
            '.statusLine = {"type": "command", "command": $cmd, "refreshInterval": 1}' \
            "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
    else
        # Create new settings.json
        cat > "$settings_file" <<SETTINGS_EOF
{
  "statusLine": {
    "type": "command",
    "command": "${statusline_cmd}",
    "refreshInterval": 1
  }
}
SETTINGS_EOF
    fi

    if is_docker; then
        chown -R root:root "$CLAUDE_DIR" 2>/dev/null || true
    else
        local user
        user=$(get_user)
        chown -R "$user:$user" "$CLAUDE_DIR" 2>/dev/null || true
    fi

    log_success "Claude Code statusline configured."
}

main() {
    log "Starting Claude Code setup..."
    install_claude_code
    setup_statusline
    log_success "Claude Code setup completed!"
}

main "$@"
