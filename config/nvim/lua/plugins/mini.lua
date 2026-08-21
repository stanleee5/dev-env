-- mini.nvim 모듈 설정
-- 각 모듈은 독립적이며, 여기서 setup()을 호출한 것만 활성화된다.
-- 이미 쓰는 플러그인과 겹치는 모듈(statusline/comment/files/pick/diff 등)은 켜지 않음.

-- 감싸기: saiw" (단어 감싸기) / sd" (제거) / sr"' (변경)
-- 주의: normal 모드의 기본 s(치환)를 s-prefix가 가려간다. 대신 cl 사용.
require("mini.surround").setup()

-- 텍스트오브젝트 확장: ci( va" cia(인자) vaf(함수 호출) cit(태그)
-- 여기에 next/last 수식어가 붙는다: cin( = 다음 괄호 안, cil( = 이전 괄호 안
require("mini.ai").setup({ n_lines = 500 })

-- 괄호/따옴표 자동 짝맞춤
-- <CR>은 매핑하지 않으므로 blink.cmp의 <CR>(enter preset) 확정 키와 충돌하지 않는다.
require("mini.pairs").setup()

-- 줄/블록 이동: Alt+j/k (위아래), Alt+h/l (좌우 들여쓰기)
-- 터미널에서 Option 키가 안 먹으면 iTerm2 > Profiles > Keys에서
-- Left Option Key를 "Esc+"로 설정해야 한다.
require("mini.move").setup()

-- 하이라이트: #ff0000 같은 색상코드를 실제 색으로, TODO/FIXME/NOTE 강조
local hipatterns = require("mini.hipatterns")
hipatterns.setup({
  highlighters = {
    fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
    hack  = { pattern = "%f[%w]()HACK()%f[%W]",  group = "MiniHipatternsHack"  },
    todo  = { pattern = "%f[%w]()TODO()%f[%W]",  group = "MiniHipatternsTodo"  },
    note  = { pattern = "%f[%w]()NOTE()%f[%W]",  group = "MiniHipatternsNote"  },
    hex_color = hipatterns.gen_highlighter.hex_color(),
  },
})
