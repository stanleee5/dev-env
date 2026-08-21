ARG BASE_IMAGE=ubuntu:20.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    DOCKER_BUILD=true \
    ZDOTDIR=/workspace \
    HOME=/workspace \
    XDG_CONFIG_HOME=/workspace/.config \
    XDG_DATA_HOME=/workspace/.local/share \
    XDG_CACHE_HOME=/workspace/.cache
WORKDIR /workspace

COPY config/apt-packages.txt /workspace/setups/config/
# Swap apt mirror to a Korean mirror. archive.ubuntu.com is unreachable on
# port 80 from some build environments; mirror.kakao.com is fast and reliable.
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do \
        if [ -f "$f" ]; then sed -i \
            -e 's|https\?://archive\.ubuntu\.com/ubuntu/\?|http://mirror.kakao.com/ubuntu/|g' \
            -e 's|https\?://security\.ubuntu\.com/ubuntu/\?|http://mirror.kakao.com/ubuntu/|g' \
            -e 's|https\?://[a-z]\{2\}\.archive\.ubuntu\.com/ubuntu/\?|http://mirror.kakao.com/ubuntu/|g' \
            "$f"; fi; \
    done && \
    apt-get update -y && \
    grep -v '^\s*#' /workspace/setups/config/apt-packages.txt | grep -v '^\s*$' | \
    xargs apt-get install -y --no-install-recommends \
    && ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone \
    && mkdir -p /etc/sudoers.d \
    && rm -rf /var/lib/apt/lists/*

# Common utilities (used by all scripts)
COPY scripts/utils.sh /workspace/setups/scripts/

# Tmux
COPY config/tmux.conf /workspace/setups/config/
COPY scripts/install_tmux.sh /workspace/setups/scripts/
RUN bash /workspace/setups/scripts/install_tmux.sh

# Zsh
COPY scripts/install_zsh.sh /workspace/setups/scripts/
RUN bash /workspace/setups/scripts/install_zsh.sh

ENV SHELL=/usr/bin/zsh

# Python (skip if already available, e.g. via conda/miniconda in base image)
RUN if ! command -v python3 >/dev/null 2>&1; then \
        apt-get update -y && \
        apt-get install -y --no-install-recommends python3-pip python3-dev && \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo "Python already available: $(python3 --version)"; \
    fi
ENV PIP_BREAK_SYSTEM_PACKAGES=1
COPY config/requirements.txt /workspace/setups/config/
COPY scripts/install_python.sh /workspace/setups/scripts/
RUN bash /workspace/setups/scripts/install_python.sh

# Node.js (required for pyright LSP, Neovim plugins, and Claude Code)
ARG NODE_MAJOR=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x -o /tmp/nodesource_setup.sh && \
    bash /tmp/nodesource_setup.sh && \
    rm /tmp/nodesource_setup.sh && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && \
    npm --version

# Neovim
COPY config/nvim /workspace/setups/config/nvim
COPY scripts/install_nvim.sh /workspace/setups/scripts/
RUN bash /workspace/setups/scripts/install_nvim.sh

# Claude Code + statusline
COPY config/claude /workspace/setups/config/claude
COPY scripts/install_claude.sh /workspace/setups/scripts/
RUN bash /workspace/setups/scripts/install_claude.sh
ENV PATH="/workspace/.claude/bin:${PATH}"

CMD ["sleep", "infinity"]
