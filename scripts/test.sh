#!/bin/bash
# ==============================================================================
# Setup Verification Script
#
# Verifies that all tools installed by the setup scripts are working correctly.
# ==============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# 카운터 증가는 반드시 X=$((X + 1)) 형태로 한다. ((X++))는 후위 증가라 X=0일 때
# 반환값이 0 -> exit status 1이 되고, utils.sh의 set -e가 스크립트를 죽인다.
PASS=0
FAIL=0

check() {
    local description="$1"
    local command="$2"
    if eval "$command" >/dev/null 2>&1; then
        log_success "$description"
        PASS=$((PASS + 1))
    else
        log_error "$description"
        FAIL=$((FAIL + 1))
    fi
}

check_output() {
    local description="$1"
    local command="$2"
    local result
    if result=$(eval "$command" 2>&1); then
        log_success "$description: $result"
        PASS=$((PASS + 1))
    else
        log_error "$description: FAILED"
        FAIL=$((FAIL + 1))
    fi
}

display_color_band() {
    awk 'BEGIN{
        s="/\\/\\/\\/\\/\\"; s=s s s s s s s s;
        for (colnum = 0; colnum<77; colnum++) {
            r = 255-(colnum*255/76);
            g = (colnum*510/76);
            b = (colnum*255/76);
            if (g>255) g = 510-g;
            printf "\033[48;2;%d;%d;%dm", r,g,b;
            printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b;
            printf "%s\033[0m", substr(s,colnum+1,1);
        }
        printf "\n";
    }'
}

main() {
    display_color_band
    log "Running setup verification..."
    echo

    # Timezone (UTC+9 / KST)
    check_output "Timezone"         "date '+%Z %z'"
    check        "Timezone is UTC+9" "[[ \"\$(date '+%z')\" == \"+0900\" ]]"

    # Shell tools
    check_output "Zsh"        "zsh --version | head -n1"
    check        "Oh My Zsh"  "[[ -d \"\$(get_base_dir)/.oh-my-zsh\" ]]"
    check_output "Tmux"            "tmux -V"
    check        "TPM installed"   "[[ -x \"\$(get_base_dir)/.config/tmux/plugins/tpm/tpm\" ]]"
    check        "tmux-powerkit plugin" "[[ -d \"\$(get_base_dir)/.config/tmux/plugins/tmux-powerkit\" ]]"
    # A present-but-non-loading plugin is the failure mode that actually bites:
    # tmux-powerkit refusing to start makes `run tpm` exit non-zero, which aborts
    # TPM before it sources anything, and tmux quietly falls back to its built-in
    # status bar. The existence check above passes right through that.
    check        "tmux-powerkit loads" "bash \"\$(get_base_dir)/.config/tmux/plugins/tmux-powerkit/tmux-powerkit.tmux\" >/dev/null 2>&1"

    # Python
    check_output "Python3"    "python3 --version"
    check        "pip"        "command -v pip3 || command -v pip"

    # Neovim
    check_output "Neovim"        "nvim --version | head -n1"
    check        "Neovim config" "[[ -f \"\${XDG_CONFIG_HOME:-\$(get_base_dir)/.config}/nvim/init.lua\" ]]"

    # LSP servers (native LSP)
    check "pyright-langserver"   "command -v pyright-langserver"
    check "ruff"                 "command -v ruff"
    check "bash-language-server" "command -v bash-language-server"
    check "lua-language-server"  "command -v lua-language-server"
    check "json-language-server"  "command -v vscode-json-language-server"
    check "yaml-language-server"  "command -v yaml-language-server"
    check "taplo"                "command -v taplo"
    check "marksman"             "command -v marksman"

    # Node.js
    check_output "Node.js" "node --version"
    check_output "npm"     "npm --version"

    # Common tools
    check "curl"          "command -v curl"
    check "git"           "command -v git"
    check "ripgrep (rg)"  "command -v rg"
    check "jq"            "command -v jq"

    echo
    log "Results: ${PASS} passed, ${FAIL} failed"
    if [[ "$FAIL" -gt 0 ]]; then
        log_error "Some checks failed!"
        exit 1
    else
        log_success "All checks passed!"
    fi
}

main "$@"
