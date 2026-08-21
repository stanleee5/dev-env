-- nvim-scrollbar
--
-- 기본값은 handle 색이 CursorColumn(everforest 기준 #3a464c, 거의 검정)에
-- blend=30이 얹힌다. init.lua가 everforest_transparent_background를 켜서
-- Normal의 bg가 NONE이므로, 어두운 핸들이 터미널 배경에 그대로 묻혀 안 보인다.
-- PmenuThumb는 "스크롤바 썸"용으로 테마가 직접 정의하는 그룹이라
-- (everforest: #7a8478) 대비가 확실하고, 테마를 바꿔도 함께 따라간다.

require("scrollbar").setup({
  handle = {
    highlight = "PmenuThumb",
    blend = 0, -- 투명 배경에선 블렌드가 곧 대비 손실이다
  },
  marks = {
    -- 진단/검색 마커는 fg를 쓰므로 핸들 위에서도 그대로 읽힌다.
    Search = { highlight = "Search" },
  },
})
