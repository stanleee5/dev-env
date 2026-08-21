# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A portable Docker-based dev-environment bootstrap. It takes an arbitrary base image (typically an ML/AI training image such as `sglang`, `axolotl`, PyTorch, etc.) and layers on a standard developer toolchain: Zsh + Oh My Zsh, Tmux, Neovim (lazy.nvim + native LSP: pyright/ruff/bashls/lua_ls, blink.cmp), Python dev deps, Node.js, and Claude Code with a custom statusline.

The same install scripts are designed to run **both inside `docker build` and on a host machine**. This dual-mode behavior is the central design constraint — do not break it.

## Common commands

Build a dev image locally (tags as `${IMAGE_PREFIX:-dev}/<image-name>`):
```bash
bash build.sh <base_image>
# e.g. bash build.sh lmsysorg/sglang:v0.5.9
```

Verify a running image/host has all tools installed and working:
```bash
bash scripts/test.sh
```

Run a single install script standalone (each is idempotent and works on host or in container):
```bash
bash scripts/install_zsh.sh
bash scripts/install_nvim.sh [v0.11.3]   # optional version arg
bash scripts/install_python.sh
bash scripts/install_tmux.sh
bash scripts/install_claude.sh
```

There is no lint step or test framework beyond `scripts/test.sh`.

## Architecture

### Layering contract (`dockerfile`)

The Dockerfile is carefully ordered so that cheap changes don't invalidate expensive layers. Each tool has a tight `COPY config/... && COPY scripts/install_X.sh && RUN install_X.sh` triple. **When adding a new tool, preserve this structure** and place it after apt/tmux so the big apt layer stays cached.

Key env vars set globally in the Dockerfile:
- `HOME=/workspace`, `ZDOTDIR=/workspace`, `XDG_CONFIG_HOME=/workspace/.config` — user-state lives on `/workspace`, not `/root`. This matters because `/workspace` is typically a mounted volume, so dotfiles persist across container restarts.
- `DOCKER_BUILD=true` — forces `is_docker()` to return true during the build, even before `/.dockerenv` exists.
- `PIP_BREAK_SYSTEM_PACKAGES=1` — required for `pip install` on Ubuntu 24+ without a venv.

The APT mirror in `sources.list` is rewritten to `mirror.kakao.com` inside the Dockerfile because `archive.ubuntu.com:80` is unreachable from some build environments. Don't remove this.

### `scripts/utils.sh` — the shared contract

Every install script sources this file. It's guarded by `BASH_UTILS_LOADED` so double-sourcing is safe, and it applies `set -euo pipefail` to every script that sources it.

The utilities that the install scripts rely on:
- `is_docker` / `detect_environment` — returns `docker` if `/.dockerenv` exists, `docker` is in `/proc/1/cgroup`, or `DOCKER_BUILD=true`. Otherwise `root`, `sudo`, or `user`.
- `get_base_dir` — returns `/workspace` in Docker, `$HOME` elsewhere. This is the single source of truth for where dotfiles go.
- `is_non_interactive` — true in Docker/CI or when `DEBIAN_FRONTEND=noninteractive`; `confirm()` auto-accepts or auto-declines based on this, so scripts can run unattended in `docker build`.
- `run_privileged <cmd>` — runs directly in docker/root, via `sudo` otherwise. Use this for any apt / /etc mutation; do not call `sudo` or `apt-get` directly.
- `add_block_to_shell_configs <block> [check_pattern]` — idempotently appends to `.zshrc` and `.bashrc` under `get_base_dir`. Always prefer this over raw `echo >>`.
- Logging: `log`, `log_success`, `log_warning`, `log_error` — all tee to `/tmp/setup.log`.

### Dual-mode path logic

Every script that touches a path chooses between `/workspace` (Docker) and `$HOME` (host). The canonical pattern:
```bash
if is_docker; then
    readonly TARGET="/workspace/..."
else
    readonly TARGET="$(get_user_home)/..."
fi
```
`install_zsh.sh` additionally respects a pre-set `ZDOTDIR` (the Dockerfile sets it to `/workspace`). `install_nvim.sh` installs the binary to `$BASE_DIR/nvim/` and exposes it by appending `export PATH="$BASE_DIR/nvim/bin:$PATH"` plus `alias vim=nvim` to the shell rcs (no `/usr/local/bin` symlink — non-interactive `vim` invocations still resolve to the apt `vim` package). When modifying install scripts, keep both branches correct — running `bash scripts/install_*.sh` on the host must not clobber the user's real `$HOME` with Docker-layout assumptions.

### Neovim specifics (`config/nvim/`)

- `init.lua` bootstraps `lazy.nvim` and declares plugins. `install_nvim.sh` runs `nvim --headless +Lazy! sync +qa` during the build so `lazy-lock.json` gets generated and plugin versions are pinned into the image.
- The LSP layer is native (`vim.lsp.config`/`vim.lsp.enable`, nvim 0.11+) with `nvim-lspconfig` providing server definitions and `blink.cmp` providing completion. All LSP setup — server settings, diagnostics, keymaps — lives in `config/nvim/lua/plugins/lsp.lua`. Servers: `pyright` (Python types), `bash-language-server`, `jsonls` (`vscode-langservers-extracted`), `yamlls`, and `taplo` (all npm, via `install_language_servers` in `install_nvim.sh`), `ruff` (Python lint/format; from `config/requirements.txt` via pip), and `lua-language-server` + `marksman` (GitHub release binaries, Linux x64 only — macOS hosts use brew). `jsonls`/`yamlls` get their schema catalog from `b0o/schemastore.nvim` (declared as an nvim-lspconfig dependency in `init.lua`); yamlls additionally maps the `kubernetes` schema onto k8s-ish globs but deliberately not `templates/` (Helm templates aren't valid YAML). A server is only enabled if its binary is on PATH; `shellcheck` (apt) gives bashls linting. `config/nvim/.luarc.json` is the lua_ls root marker — without one lua_ls runs in single-file mode and publishes no diagnostics (and note `copy_config` uses `cp -r "$src"/.` so dotfiles like it get copied).
- `blink.cmp` is pinned to `version = "1.*"` so it downloads a prebuilt Rust fuzzy-matcher binary; `install_nvim.sh` waits for that download during the build so it's baked into the image, and `fuzzy.implementation = "prefer_rust"` falls back to the Lua matcher if it's missing.
- Node.js (installed from NodeSource in the Dockerfile) is a hard dependency here — both pyright and Claude Code require it.
- Per-plugin config lives in `config/nvim/lua/plugins/{lsp,lualine,mini,nvim-tree,comment}.lua`.

### Claude Code (`scripts/install_claude.sh`, `config/claude/statusline.sh`)

Installs `@anthropic-ai/claude-code` (latest) via npm (falls back to the official curl installer if npm is missing). Then copies `config/claude/statusline.sh` into `$CLAUDE_DIR/scripts/` and merges a `statusLine` entry into `$CLAUDE_DIR/settings.json` using `jq` (so existing settings are preserved).

The statusline parses the JSON that Claude Code pipes on stdin and renders a 2-line prompt with model name, git branch + staged/modified counts, worktree, context usage bar, token counts, cost, and 5h/7d rate-limit windows. If you change the status JSON schema expected by Claude Code, update the `jq` extraction at the top.

## Conventions when editing

- New install scripts must `source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"` as their first real line, and follow the `main()` / `main "$@"` pattern used by all existing scripts.
- Use `$CONFIG_DIR` (exported by utils.sh, resolves to `<repo>/config`) rather than hard-coded paths when referencing configs from scripts.
- Keep `config/apt-packages.txt` and `config/requirements.txt` as the single sources of truth for system + Python packages; don't inline package lists into the Dockerfile or scripts.
- `.dockerignore` excludes `.git`, `*.md`, `build.sh`, `internal/`, and `scripts/test.sh` from the build context — don't rely on any of those being present inside the image.
