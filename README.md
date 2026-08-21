# dev-env

> **English** | [한국어](README.ko.md)

Portable, Docker-based dev-environment bootstrap.

Take any base image — typically an ML/AI training image (`sglang`, `axolotl`, PyTorch, …) — and layer a full developer toolchain on top of it. The same install scripts also run directly on a host machine, so you can use this repo both to build dev images and to set up a fresh server.

## What you get

| Tool | Details |
|---|---|
| **Zsh** | Oh My Zsh, sensible defaults |
| **Tmux** | TPM + [tmux-powerkit](https://github.com/fabioluciano/tmux-powerkit) (tokyo-night) |
| **Neovim** | lazy.nvim, native LSP (pyright, ruff, bashls, lua_ls, jsonls, yamlls, taplo, marksman — JSON/YAML get schemastore-backed completion, incl. k8s manifests), blink.cmp, treesitter — plugins pre-synced into the image |
| **Python** | dev/notebook essentials from `config/requirements.txt` (ruff, black, jupyterlab, nvitop, …) |
| **Node.js** | for the npm-based LSP servers (pyright, bashls, jsonls, yamlls, taplo); also used to install Claude Code |
| **Claude Code** | latest, plus a custom 2-line statusline (git status, context bar, cost, rate limits) |

## Build a dev image

```bash
bash build.sh lmsysorg/sglang:v0.5.9
# → builds and tags dev/sglang:v0.5.9
```

The tag prefix defaults to `dev/`; override with `IMAGE_PREFIX=myprefix bash build.sh <base_image>`.

Run it with `/workspace` mounted so your dotfiles and shell history survive container restarts:

```bash
docker run -it --gpus all -v "$PWD:/workspace" dev/sglang:v0.5.9 zsh
```

`HOME`, `ZDOTDIR`, and the XDG dirs all point at `/workspace` inside the image — user state lives on the volume, not in the container layer.

## Set up a host machine

Every script is idempotent and detects whether it's running in Docker, as root, or as a regular user (sudo where needed):

```bash
bash scripts/install_zsh.sh
bash scripts/install_tmux.sh
bash scripts/install_nvim.sh [v0.11.3]   # optional version arg
bash scripts/install_python.sh
bash scripts/install_claude.sh
```

On a host, dotfiles go to `$HOME` instead of `/workspace`.

## Verify

```bash
bash scripts/test.sh
```

Checks that every tool is installed and functional (inside a container or on a host).

## Layout

```
build.sh                  # docker build wrapper
dockerfile                # layered so cheap changes don't bust expensive caches
config/
  apt-packages.txt        # single source of truth for system packages
  requirements.txt        # single source of truth for python packages
  tmux.conf
  nvim/                   # init.lua + lua/plugins/*
  claude/statusline.sh
scripts/
  utils.sh                # shared helpers: env detection, privileged exec, logging
  install_*.sh            # one tool per script, host + docker dual-mode
  test.sh
```

## Design notes

- **Dual-mode is the core constraint**: every install script must work both inside `docker build` and on a live host. `scripts/utils.sh` provides the environment detection (`is_docker`, `get_base_dir`, `run_privileged`) that makes this possible.
- The Dockerfile copies each tool's config + script as a tight pair, so editing one tool's config only invalidates that tool's layer.
- The APT mirror is switched to `mirror.kakao.com` because `archive.ubuntu.com:80` is unreachable from some build environments.
