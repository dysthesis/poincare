local MiniTest = require("mini.test")
local root = vim.fs.dirname(
  vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
)
local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart()
      child.lua(
        [[
        vim.opt.runtimepath:prepend(...)
        vim.opt.packpath:prepend(assert(vim.env.POINCARE_PACKPATH))
        vim.cmd.packadd("nvim-treesitter-grammar-lua")
        vim.cmd.packadd("nvim-treesitter-grammar-rust")
        require("lang.modules.fold")({ filetypes = { "lua", "rust" } }, true)
        vim.treesitter.query.add_directive(
          "fold-priority!",
          function(_, _, _, predicate, metadata)
            metadata.priority = assert(tonumber(predicate[2]))
          end,
          {}
        )
      ]],
        { root .. "/src" }
      )
    end,
    post_once = child.stop,
  },
})

local function refresh()
  child.lua("vim.treesitter.get_parser(0):parse()")
  child.cmd("normal! zxzM")
end

local function fold(lines, query, lang)
  child.lua(
    [[
    local lines, query, lang = ...
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.treesitter.query.set(lang, "highlights", query)
    vim.bo.filetype = lang
    vim.treesitter.start(0, lang)
  ]],
    { lines, query, lang or "lua" }
  )
  refresh()
end

local function chunks(row, win)
  return child.lua(
    [[
    local row, win = ...
    return vim.api.nvim_win_call(win, function()
      local render = vim.wo.foldtext
      local result
      -- Observe raw chunks in the real foldtext evaluation context.
      vim.wo.foldtext = function()
        result = render()
        return result
      end
      vim.fn.foldtextresult(row)
      vim.wo.foldtext = render
      return result
    end)
  ]],
    { row or 1, win or 0 }
  )
end

T["unhighlighted tails preserve UTF-8, tabs and text before the folded node"] = function()
  fold({
    "\tlocal label = 'λ雪'; function alpha()\t-- plain \t  ",
    "  return label",
    "end",
  }, "(identifier) @function")

  eq(child.fn.foldclosed(1), 1)
  eq(child.fn.foldclosedend(1), 3)
  eq(chunks(), {
    { "\tlocal " },
    { "label", "@function" },
    { " = 'λ雪'; function " },
    { "alpha", "@function" },
    { "()\t-- plain" },
    { "  … 3 lines …", "Comment" },
  })
end

T["overlapping captures use numeric priorities and later equal-priority captures"] = function()
  fold(
    { "function alpha(argument)  ", "  return argument", "end" },
    [[
    (function_declaration) @fold.base
    ((function_declaration) @fold.string (#set! priority "999"))
    ((identifier) @fold.earlier (#fold-priority! "150"))
    ((identifier) @fold.later
      (#fold-priority! "150")
      (#offset! @fold.later 0 1 0 -1))
    ((identifier) @fold.lower (#fold-priority! "120"))
  ]]
  )

  eq(chunks(), {
    { "function ", "@fold.string" },
    { "alpha", "@fold.later" },
    { "(", "@fold.string" },
    { "argument", "@fold.later" },
    { ")", "@fold.string" },
    { "  … 3 lines …", "Comment" },
  })
end

T["root and injected capture precedence updates when the injection disappears"] = function()
  child.lua(
    [[
    local injections, highlights = ...
    vim.treesitter.query.set("lua", "injections", injections)
    vim.treesitter.query.set("rust", "highlights", highlights)
  ]],
    {
      [[
      ((string content: (string_content) @injection.content)
        (#lua-match? @injection.content "^fn ")
        (#set! injection.language "rust"))
    ]],
      [[
      ((function_item) @fold.injected.lower (#fold-priority! "120"))
      ((identifier) @fold.injected.earlier (#fold-priority! "150"))
      ((identifier) @fold.injected.later (#fold-priority! "150"))
      ((integer_literal) @fold.injected.higher (#fold-priority! "200"))
    ]],
    }
  )
  local header = "function outer() local source = [[fn 雪() { 1 }]] -- λ"
  local fn_col = assert(header:find("fn ", 1, true)) - 1
  local name_col = assert(header:find("雪", 1, true)) - 1
  local number_col = assert(header:find("1", 1, true)) - 1
  fold(
    { header, "  return source", "end" },
    '((string) @fold.root (#fold-priority! "150"))'
  )
  -- parse() alone only parses the root; the fixture must prepare injections.
  child.lua("vim.treesitter.get_parser(0):parse(true)")
  child.cmd("normal! zxzM")

  local function captures_at(col)
    return child.lua(
      [[
      return vim.tbl_map(function(capture)
        return { capture.lang, capture.capture, capture.metadata.priority }
      end, vim.treesitter.get_captures_at_pos(0, 0, ...))
    ]],
      { col }
    )
  end

  -- Native capture order establishes the oracle independently of fold chunks:
  -- numeric priority beats the later subtree, while equal priorities use its
  -- later capture. Probe both ends of the multibyte identifier and the next byte.
  local enclosing = {
    { "lua", "fold.root", 150 },
    { "rust", "fold.injected.lower", 120 },
  }
  local identifier = {
    { "lua", "fold.root", 150 },
    { "rust", "fold.injected.lower", 120 },
    { "rust", "fold.injected.earlier", 150 },
    { "rust", "fold.injected.later", 150 },
  }
  eq(captures_at(fn_col), enclosing)
  eq(captures_at(name_col), identifier)
  eq(captures_at(name_col + #"雪" - 1), identifier)
  eq(captures_at(name_col + #"雪"), enclosing)
  eq(captures_at(number_col), {
    { "lua", "fold.root", 150 },
    { "rust", "fold.injected.lower", 120 },
    { "rust", "fold.injected.higher", 200 },
  })
  eq(child.fn.foldclosed(1), 1)
  eq(child.fn.foldclosedend(1), 3)
  eq(chunks(), {
    { "function outer() local source = " },
    { "[[fn ", "@fold.root" },
    { "雪", "@fold.injected.later" },
    { "() { ", "@fold.root" },
    { "1", "@fold.injected.higher" },
    { " }]]", "@fold.root" },
    { " -- λ" },
    { "  … 3 lines …", "Comment" },
  })

  child.lua(
    [[
    local col = ...
    vim.api.nvim_buf_set_text(0, 0, col, 0, col + 2, { "no" })
    vim.treesitter.get_parser(0):parse(true)
  ]],
    { fn_col }
  )
  child.cmd("normal! zxzM")
  local root_only = { { "lua", "fold.root", 150 } }
  eq(captures_at(name_col), root_only)
  eq(captures_at(number_col), root_only)
  eq(chunks(), {
    { "function outer() local source = " },
    { "[[no 雪() { 1 }]]", "@fold.root" },
    { " -- λ" },
    { "  … 3 lines …", "Comment" },
  })
end

T["edit and undo refresh the header text and capture boundaries"] = function()
  local original = { "function alpha() -- original", "  return 1", "end" }
  fold(
    original,
    [[
    "function" @keyword
    ((identifier) @function (#eq? @function "alpha"))
  ]]
  )
  local initial = {
    { "function", "@keyword" },
    { " " },
    { "alpha", "@function" },
    { "() -- original" },
    { "  … 3 lines …", "Comment" },
  }
  eq(chunks(), initial)

  child.cmd("normal! zR")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("cc", "function beta() -- changed", "<Esc>")
  refresh()
  eq(chunks(), {
    { "function", "@keyword" },
    { " beta() -- changed" },
    { "  … 3 lines …", "Comment" },
  })

  child.type_keys("u")
  refresh()
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), original)
  eq(chunks(), initial)
end

T["windows keep independent fold state and buffers keep their own headers"] = function()
  fold({ "function first()", "  return 1", "end" }, '"function" @keyword')
  local first_win = child.api.nvim_get_current_win()
  local first_chunks = {
    { "function", "@keyword" },
    { " first()" },
    { "  … 3 lines …", "Comment" },
  }

  child.cmd("vsplit")
  local second_win = child.api.nvim_get_current_win()
  child.cmd("normal! zR")
  eq(child.fn.foldclosed(1), -1)
  eq(chunks(1, first_win), first_chunks)
  child.cmd("normal! zM")
  eq(chunks(), first_chunks)

  child.cmd("enew")
  fold({
    "function second()",
    "  local value = 2",
    "  return value",
    "end",
  }, '"function" @keyword')
  local second_chunks = {
    { "function", "@keyword" },
    { " second()" },
    { "  … 4 lines …", "Comment" },
  }
  eq(child.fn.foldclosedend(1), 4)
  eq(chunks(), second_chunks)
  eq(chunks(1, first_win), first_chunks)
  child.api.nvim_set_current_win(first_win)
  eq(chunks(), first_chunks)
  child.api.nvim_set_current_win(second_win)
  eq(chunks(), second_chunks)
end

T["a stopped highlighter leaves the whole trimmed header readable"] = function()
  fold(
    { "function alpha() -- λ雪\t  ", "  return 1", "end" },
    '"function" @keyword'
  )
  child.lua("vim.treesitter.stop(0)")

  eq(chunks(), {
    { "function alpha() -- λ雪" },
    { "  … 3 lines …", "Comment" },
  })
end

T["a missing highlight query keeps plain Rust text and its closing brace"] = function()
  fold({ "fn alpha() { \t", "    let value = 1;", "}" }, "", "rust")

  eq(child.fn.foldclosed(1), 1)
  eq(child.fn.foldclosedend(1), 3)
  eq(chunks(), {
    { "fn alpha() {" },
    { "  … 3 lines …", "Comment" },
    { " }", "@punctuation.bracket" },
  })
end

return T
