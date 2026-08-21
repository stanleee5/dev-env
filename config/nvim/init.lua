-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Disable netrw (required before nvim-tree loads)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Plugin specs
require("lazy").setup({
  "tpope/vim-sensible",

  { "nvim-lualine/lualine.nvim",
    config = function() require("plugins.lualine") end,
  },

  { "nvim-telescope/telescope.nvim",
    branch = "master",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  { "nvim-tree/nvim-web-devicons",
    config = function()
      require("nvim-web-devicons").setup({ default = true })
    end,
  },

  { "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function() require("plugins.nvim-tree") end,
  },

  { "nvim-treesitter/nvim-treesitter",
    -- main 브랜치는 configs 모듈을 삭제했다. 아래 setup()은 master 계열 API.
    branch = "master",
    build = ":TSUpdate",
    config = function()
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      if not ok then
        -- 조용히 넘어가면 파서 0개 + highlight 꺼진 상태로 이미지가 만들어진다.
        vim.notify("nvim-treesitter.configs 로드 실패: " .. tostring(configs), vim.log.levels.ERROR)
        return
      end
      configs.setup({
        ensure_installed = {"bash", "json", "python", "c", "cpp", "cuda", "lua",
                            "markdown", "markdown_inline"},
        sync_install = true,
        highlight = { enable = true },
        indent = { enable = true },
      })

      -- nvim 0.12는 add_directive의 all=false 호환을 없애서 match[id]가 노드 하나가
      -- 아니라 노드 리스트로 넘어온다. 아카이브된 nvim-treesitter master의 디렉티브는
      -- 이걸 모르고 노드처럼 다뤄서 markdown 코드펜스/bash heredoc injection 파싱이
      -- 통째로 터진다(attempt to call method 'range'). 리스트를 아는 구현으로 덮어쓴다.
      -- 0.11 이하(구버전 이미지)에서는 조건이 false라 아무 일도 안 한다.
      if vim.fn.has("nvim-0.12") == 1 then
        local query = require("vim.treesitter.query")
        local dopts = { force = true, all = true }
        local function capture_node(match, id)
          local m = match[tonumber(id)]
          if type(m) == "table" then return m[#m] end
          return m
        end

        query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
          local node = capture_node(match, pred[2])
          if not node then return end
          local alias = vim.treesitter.get_node_text(node, bufnr):lower()
          metadata["injection.language"] = vim.treesitter.language.get_lang(alias) or alias
        end, dopts)

        query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
          local id = tonumber(pred[2])
          local node = capture_node(match, id)
          if not node then return end
          local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[id] }) or ""
          if not metadata[id] then metadata[id] = {} end
          metadata[id].text = text:lower()
        end, dopts)
      end
    end,
  },

  -- 마크다운을 버퍼 안에서 바로 렌더한다(브라우저/외부 프로세스 불필요).
  -- markdown/markdown_inline 파서가 위 ensure_installed에 있어야 동작한다.
  { "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    ft = { "markdown" },
    opts = {},
    keys = {
      { "<leader>m", "<cmd>RenderMarkdown buf_toggle<cr>",
        ft = "markdown", desc = "Markdown 렌더 토글" },
    },
  },

  { "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup()
      vim.keymap.set("n", "gt", ":BufferLineCycleNext<CR>", { noremap = true, silent = true })
      vim.keymap.set("n", "gT", ":BufferLineCyclePrev<CR>", { noremap = true, silent = true })
    end,
  },

  -- Native LSP (nvim 0.11+): 서버 정의는 nvim-lspconfig, 설정/키맵은 plugins/lsp.lua
  { "neovim/nvim-lspconfig",
    dependencies = { "saghen/blink.cmp" },
    config = function() require("plugins.lsp") end,
  },

  { "saghen/blink.cmp",
    version = "1.*", -- 릴리스 태그 고정 → 프리빌트 fuzzy 바이너리를 다운로드한다
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "enter", -- <CR>로 확정 (coc 시절 습관 유지)
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      signature = { enabled = true },
      -- Rust 바이너리가 없으면 조용히 Lua 매처로 폴백 (다운로드 실패해도 동작)
      fuzzy = { implementation = "prefer_rust" },
    },
  },

  { "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup()
    end,
  },

  { "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("diffview").setup({
        use_icons = true,
      })
      vim.keymap.set("n", "<leader>dx", function()
        local current = vim.o.diffopt
        if current:match("context:999") then
          vim.o.diffopt = current:gsub("context:999", "context:6")
          vim.notify("Diff context: changes only")
        else
          vim.o.diffopt = current:gsub("context:%d+", "context:999")
          vim.notify("Diff context: full file")
        end
      end, { noremap = true, silent = true, desc = "Toggle diff context" })
      local diffview_open = false
      vim.keymap.set("n", "<leader>dv", function()
        if diffview_open then
          vim.cmd("DiffviewClose")
          diffview_open = false
        else
          vim.cmd("DiffviewOpen")
          diffview_open = true
        end
      end, { noremap = true, silent = true, desc = "Toggle Diffview" })
      vim.keymap.set("n", "<leader>df", ":DiffviewFileHistory %<CR>", { noremap = true, silent = true, desc = "Diffview file history" })
      vim.keymap.set("n", "<leader>dh", ":DiffviewFileHistory<CR>", { noremap = true, silent = true, desc = "Diffview branch history" })
    end,
  },

  { "numToStr/Comment.nvim",
    config = function() require("plugins.comment") end,
  },

  { "petertriho/nvim-scrollbar",
    config = function() require("plugins.scrollbar") end,
  },

  -- themes
  "olimorris/onedarkpro.nvim",
  "maxmx03/fluoromachine.nvim",
  { "sainnhe/everforest", priority = 1000 },

  { "echasnovski/mini.nvim", version = false,
    config = function() require("plugins.mini") end,
  },
})

-- Theme - everforest
vim.opt.termguicolors = true
vim.g.everforest_background = "soft"
vim.g.everforest_better_performance = 1
vim.g.everforest_enable_italic = 1
vim.g.everforest_transparent_background = 1
local ok, _ = pcall(vim.cmd, "colorscheme everforest")
if not ok then
  vim.notify("colorscheme 'everforest' not found — run :Lazy sync", vim.log.levels.WARN)
end

-- --- 시각적 설정 ---
vim.o.syntax = "on"           -- 구문 강조
vim.o.background = "dark"     -- 배경 색상 설정
vim.o.termguicolors = true    -- 24비트 색상 지원

-- --- 기본 옵션 설정 ---
vim.o.encoding = "utf-8"
vim.o.fileencoding = "utf-8"

vim.o.number = true           -- 라인 번호 표시
vim.o.relativenumber = false  -- 상대 라인 번호 표시
vim.o.cursorline = true       -- 커서 라인 강조
vim.o.showcmd = true          -- 명령어 입력 중에 표시
vim.o.ruler = true            -- 상태 줄에 커서 위치 표시
vim.o.mouse = ""              -- 마우스 사용 가능
vim.o.clipboard = "unnamedplus" -- 시스템 클립보드 사용

-- copy는 OSC 52로 호스트 클립보드 전송, paste는 Lua 캐시에서 복원 (터미널 OSC 52 read는 비신뢰)
do
  local osc52 = require("vim.ui.clipboard.osc52")
  local cache = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
  local function copy(reg)
    local send = osc52.copy(reg)
    return function(lines, regtype)
      cache[reg] = { lines, regtype }
      send(lines, regtype)
    end
  end
  local function paste(reg)
    return function() return cache[reg] end
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste("+"), ["*"] = paste("*") },
  }
end

-- --- 검색 옵션 ---
vim.o.ignorecase = true       -- 대소문자 구분하지 않음
vim.o.smartcase = true        -- 대문자 포함 검색 시 대소문자 구분
vim.o.hlsearch = true         -- 검색어 하이라이트
vim.o.incsearch = true        -- 실시간 검색

-- --- 들여쓰기 설정 ---
vim.o.autoindent = true       -- 자동 들여쓰기
vim.o.smartindent = true      -- 스마트 들여쓰기
vim.o.expandtab = true        -- 탭을 공백으로 변환

-- --- 파일 관리 ---
vim.o.hidden = true           -- 저장하지 않고 다른 파일로 전환 가능
vim.o.undofile = true         -- 실행 취소 파일 유지
vim.o.backup = false          -- LSP 파일 감시와의 충돌 방지 (구 coc #649)
vim.o.writebackup = false

vim.o.foldmethod = "expr"
-- 내장 foldexpr를 쓴다. nvim-treesitter master의 nvim_treesitter#foldexpr()는
-- nvim 0.11에서 쿼리 매칭이 0건이라 모든 줄이 foldlevel 0이 된다(zo 시 E490).
vim.o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.o.foldenable = false

-- --- 키 매핑 ---
vim.keymap.set("n", "<leader>e", ":NvimTreeFindFile<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-n>", ":NvimTreeToggle<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-'>", "<C-w>w", { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", ":lua vim.wo.number = not vim.wo.number<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>+', ':vertical resize +5<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>-', ':vertical resize -5<CR>', { noremap = true, silent = true })

local telescope_installed = pcall(require, 'telescope.builtin')
if telescope_installed then
  vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, { noremap = true, silent = true, desc = 'Telescope find files' })
  vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep, { noremap = true, silent = true, desc = 'Telescope live grep' })
  vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers, { noremap = true, silent = true, desc = 'Telescope buffers' })
  vim.keymap.set('n', '<leader>fh', require('telescope.builtin').help_tags, { noremap = true, silent = true, desc = 'Telescope help tags' })
end
