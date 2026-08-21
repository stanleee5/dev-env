# dev-env

> [English](README.md) | **한국어**

Docker 기반의 포터블 개발환경 부트스트랩.

임의의 베이스 이미지 — 주로 ML/AI 학습용 이미지(`sglang`, `axolotl`, PyTorch 등) — 위에 개발 툴체인 전체를 얹습니다. 같은 설치 스크립트가 호스트 머신에서도 그대로 동작하므로, 개발용 이미지를 굽는 용도와 새 서버 세팅 용도 둘 다로 쓸 수 있습니다.

## 포함된 것들

| 도구 | 상세 |
|---|---|
| **Zsh** | Oh My Zsh, 합리적인 기본값 |
| **Tmux** | TPM + [tmux-powerkit](https://github.com/fabioluciano/tmux-powerkit) (tokyo-night) |
| **Neovim** | lazy.nvim, 네이티브 LSP (pyright, ruff, bashls, lua_ls, jsonls, yamlls, taplo, marksman — JSON/YAML은 schemastore 기반 자동완성, k8s 매니페스트 포함), blink.cmp, treesitter — 플러그인이 이미지에 미리 sync됨 |
| **Python** | `config/requirements.txt`의 개발/노트북 필수 패키지 (ruff, black, jupyterlab, nvitop, …) |
| **Node.js** | npm 기반 LSP 서버(pyright, bashls, jsonls, yamlls, taplo)의 필수 의존성. Claude Code 설치에도 사용 |
| **Claude Code** | 최신 버전 + 커스텀 2줄 statusline (git 상태, 컨텍스트 바, 비용, rate limit) |

## 개발 이미지 빌드

```bash
bash build.sh lmsysorg/sglang:v0.5.9
# → dev/sglang:v0.5.9 로 빌드/태깅
```

태그 prefix 기본값은 `dev/`이며, `IMAGE_PREFIX=myprefix bash build.sh <base_image>`로 변경할 수 있습니다.

dotfiles와 셸 히스토리가 컨테이너 재시작 후에도 유지되도록 `/workspace`를 마운트해서 실행하세요:

```bash
docker run -it --gpus all -v "$PWD:/workspace" dev/sglang:v0.5.9 zsh
```

이미지 내부에서 `HOME`, `ZDOTDIR`, XDG 디렉토리가 모두 `/workspace`를 가리키므로, 사용자 상태는 컨테이너 레이어가 아닌 볼륨에 저장됩니다.

## 호스트 머신 세팅

모든 스크립트는 멱등적이며, Docker 안인지 / root인지 / 일반 유저인지 자동 감지합니다 (필요 시 sudo 사용):

```bash
bash scripts/install_zsh.sh
bash scripts/install_tmux.sh
bash scripts/install_nvim.sh [v0.11.3]   # 버전 인자 생략 가능
bash scripts/install_python.sh
bash scripts/install_claude.sh
```

호스트에서는 dotfiles가 `/workspace` 대신 `$HOME`에 설치됩니다.

## 검증

```bash
bash scripts/test.sh
```

모든 도구가 설치되어 정상 동작하는지 확인합니다 (컨테이너/호스트 공통).

## 구조

```
build.sh                  # docker build 래퍼
dockerfile                # 저렴한 변경이 비싼 캐시를 깨지 않도록 레이어링됨
config/
  apt-packages.txt        # 시스템 패키지의 single source of truth
  requirements.txt        # 파이썬 패키지의 single source of truth
  tmux.conf
  nvim/                   # init.lua + lua/plugins/*
  claude/statusline.sh
scripts/
  utils.sh                # 공용 헬퍼: 환경 감지, 권한 실행, 로깅
  install_*.sh            # 도구당 스크립트 하나, 호스트 + docker 듀얼 모드
  test.sh
```

## 설계 노트

- **듀얼 모드가 핵심 제약**: 모든 설치 스크립트는 `docker build` 안에서도, 실제 호스트에서도 동작해야 합니다. `scripts/utils.sh`가 이를 가능하게 하는 환경 감지(`is_docker`, `get_base_dir`, `run_privileged`)를 제공합니다.
- Dockerfile은 각 도구의 config + 스크립트를 짝으로 COPY하므로, 한 도구의 설정 수정은 그 도구의 레이어만 무효화합니다.
- `archive.ubuntu.com:80`이 일부 빌드 환경에서 접근 불가라 APT 미러를 `mirror.kakao.com`으로 교체합니다.
