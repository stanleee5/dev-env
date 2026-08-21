-- Native LSP (nvim 0.11+) — coc.nvim을 대체한다.
-- 서버 정의(cmd/filetypes/root_markers)는 nvim-lspconfig가 제공하고,
-- 이 파일은 서버 설정 오버라이드 + 활성화 + 진단 표시 + 키맵만 담당한다.

-- 진단 사인이 생겨도 텍스트가 밀리지 않게 signcolumn 상시 표시
vim.opt.signcolumn = "yes"
-- CursorHold(심볼 하이라이트) 반응 속도 (기본 4000ms는 너무 느리다)
vim.opt.updatetime = 300

-- --- 진단 표시 ------------------------------------------------------------
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
})

-- --- 서버 설정 ------------------------------------------------------------
-- blink.cmp의 completion capabilities를 모든 서버에 주입
local ok_blink, blink = pcall(require, "blink.cmp")
if ok_blink then
  vim.lsp.config("*", { capabilities = blink.get_lsp_capabilities() })
end

-- pyright: 타입 체크 (구 coc-settings.json의 설정을 그대로 이관)
vim.lsp.config("pyright", {
  settings = {
    python = {
      analysis = {
        autoSearchPaths = true,
        typeCheckingMode = "basic",
        diagnosticMode = "openFilesOnly",
      },
    },
  },
})

-- ruff: lint/format/import 정리 담당. hover는 pyright에 맡긴다.
vim.lsp.config("ruff", {
  on_attach = function(client)
    client.server_capabilities.hoverProvider = false
  end,
})

-- lua_ls: nvim 설정 편집용 — vim 전역과 런타임 라이브러리를 인식시킨다
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = { library = { vim.env.VIMRUNTIME }, checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})

-- bashls: shellcheck가 PATH에 있으면 자동으로 lint까지 수행한다

-- 바이너리가 있는 서버만 활성화 (서버 없는 호스트에서 경고 스팸 방지)
local servers = {
  pyright = "pyright-langserver",
  ruff = "ruff",
  bashls = "bash-language-server",
  lua_ls = "lua-language-server",
}
for name, bin in pairs(servers) do
  if vim.fn.executable(bin) == 1 then
    vim.lsp.enable(name)
  end
end

-- --- 진단 이동 (coc 시절 키맵 유지) ----------------------------------------
vim.keymap.set("n", "[g", function() vim.diagnostic.jump({ count = -1, float = true }) end,
  { silent = true, desc = "Previous diagnostic" })
vim.keymap.set("n", "]g", function() vim.diagnostic.jump({ count = 1, float = true }) end,
  { silent = true, desc = "Next diagnostic" })

-- --- 명령 ------------------------------------------------------------------
vim.api.nvim_create_user_command("Format", function()
  vim.lsp.buf.format({ async = true })
end, { desc = "Format current buffer via LSP" })

vim.api.nvim_create_user_command("OR", function()
  vim.lsp.buf.code_action({
    context = { only = { "source.organizeImports" }, diagnostics = {} },
    apply = true,
  })
end, { desc = "Organize imports (ruff)" })

-- --- 버퍼 로컬 키맵 --------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", {}),
  callback = function(ev)
    local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
    end

    -- 이동 (coc 시절 키맵 유지)
    map("n", "gd", vim.lsp.buf.definition, "Go to definition")
    map("n", "gD", function()
      vim.cmd("tab split")
      vim.lsp.buf.definition()
    end, "Go to definition (new tab)")
    map("n", "gy", vim.lsp.buf.type_definition, "Go to type definition")
    map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
    map("n", "K", function() vim.lsp.buf.hover({ border = "rounded" }) end, "Hover documentation")

    -- 리팩터링
    map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map({ "n", "x" }, "<leader>a", vim.lsp.buf.code_action, "Code action")
    map("n", "<leader>qf", function()
      vim.lsp.buf.code_action({
        context = { only = { "quickfix" }, diagnostics = vim.diagnostic.get(0) },
        apply = true,
      })
    end, "Apply quickfix")
    map({ "n", "x" }, "<leader>f", function() vim.lsp.buf.format({ async = true }) end, "Format")

    -- 탐색: telescope가 있으면 telescope로, 없으면 내장으로
    local ok_t, tb = pcall(require, "telescope.builtin")
    map("n", "gr", ok_t and tb.lsp_references or vim.lsp.buf.references, "References")
    if ok_t then
      map("n", "<space>o", tb.lsp_document_symbols, "Document symbols (outline)")
      map("n", "<space>s", tb.lsp_dynamic_workspace_symbols, "Workspace symbols")
      map("n", "<space>a", tb.diagnostics, "All diagnostics")
    end

    -- 커서 아래 심볼 참조 하이라이트 (구 coc CursorHold highlight)
    if client:supports_method("textDocument/documentHighlight") then
      local hl_group = vim.api.nvim_create_augroup("UserLspHighlight" .. ev.buf, {})
      vim.api.nvim_create_autocmd("CursorHold", {
        group = hl_group, buffer = ev.buf,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
        group = hl_group, buffer = ev.buf,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})
