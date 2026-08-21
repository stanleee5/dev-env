require("nvim-tree").setup({
  sort = {
    sorter = "case_sensitive",
  },
  view = {
    -- width = 40,
    adaptive_size = true,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = true,
  },
  actions = {
    open_file = {
      window_picker = {
        enable = false, -- 탭 간 창 선택 비활성화
      },
    },
  },
  update_focused_file = {
    enable = false, -- 포커스된 파일 업데이트 비활성화
    update_root = false, -- 루트 디렉토리 업데이트 비활성화
  },
})

