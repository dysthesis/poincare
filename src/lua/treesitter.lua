require("lz.n").load({
  "nvim-treesitter",
  lazy = false,
  load = function(self)
    vim.cmd.packadd(self)
    vim.cmd.packadd("nvim-treesitter-textobjects")
  end,
  after = function()
    -- Enable treesitter highlighting everywhere except LaTeX (upstream queries
    -- are still experimental there).
    vim.api.nvim_create_autocmd("FileType", {
      callback = function(event)
        if event.match ~= "latex" then
          pcall(vim.treesitter.start, event.buf, event.match)
        end
      end,
    })

    -- Textobjects configuration + keymaps
    require("nvim-treesitter-textobjects").setup({
      select = {
        lookahead = true,
        selection_modes = {
          ["@block.outer"] = "<c-v>",
          ["@frame.outer"] = "<c-v>",
          ["@statement.outer"] = "V",
          ["@assignment.outer"] = "V",
          ["@comment.outer"] = "V",
          ["@comment.inner"] = "v",
          ["@conditional.inner"] = "v",
        },
      },
      move = {
        set_jumps = true,
      },
    })

    local select = require("nvim-treesitter-textobjects.select")
    local move = require("nvim-treesitter-textobjects.move")
    local swap = require("nvim-treesitter-textobjects.swap")
    local map = vim.keymap.set

    local function map_sel(lhs, capture, desc)
      map({ "x", "o" }, lhs, function()
        select.select_textobject(capture, "textobjects")
      end, { desc = desc })
    end

    map_sel("af", "@function.outer", "TS select function outer")
    map_sel("if", "@function.inner", "TS select function inner")
    map_sel("ac", "@class.outer", "TS select class outer")
    map_sel("ic", "@class.inner", "TS select class inner")
    map_sel("aC", "@call.outer", "TS select call outer")
    map_sel("iC", "@call.inner", "TS select call inner")
    map_sel("a#", "@comment.outer", "TS select comment outer")
    map_sel("i#", "@comment.inner", "TS select comment inner")
    map_sel("ai", "@conditional.outer", "TS select conditional outer")
    map_sel("ii", "@conditional.outer", "TS select conditional outer")
    map_sel("al", "@loop.outer", "TS select loop outer")
    map_sel("il", "@loop.inner", "TS select loop inner")
    map_sel("aP", "@parameter.outer", "TS select parameter outer")
    map_sel("iP", "@parameter.inner", "TS select parameter inner")
    map_sel("aa", "@assignment.outer", "TS select assignment outer")
    map_sel("ia", "@assignment.inner", "TS select assignment inner")
    map_sel("aL", "@assignment.lhs", "TS select assignment lhs")
    map_sel("iL", "@assignment.lhs", "TS select assignment lhs")
    map_sel("aR", "@assignment.rhs", "TS select assignment rhs")
    map_sel("iR", "@assignment.rhs", "TS select assignment rhs")
    map_sel("aA", "@attribute.outer", "TS select attribute outer")
    map_sel("iA", "@attribute.inner", "TS select attribute inner")
    map_sel("ab", "@block.outer", "TS select block outer")
    map_sel("ib", "@block.inner", "TS select block inner")
    map_sel("aF", "@frame.outer", "TS select frame outer")
    map_sel("iF", "@frame.inner", "TS select frame inner")
    map_sel("an", "@number.outer", "TS select number")
    map_sel("in", "@number.inner", "TS select number")
    map_sel("aX", "@regex.outer", "TS select regex outer")
    map_sel("iX", "@regex.inner", "TS select regex inner")
    map_sel("ar", "@return.outer", "TS select return outer")
    map_sel("ir", "@return.inner", "TS select return inner")
    map_sel("as", "@statement.outer", "TS select statement")
    map_sel("ns", "@scopename.inner", "TS select scope name")

    map("n", "<leader>a", function()
      swap.swap_next("@parameter.inner", "textobjects")
    end, { desc = "TS swap parameter with next" })
    map("n", "<leader>A", function()
      swap.swap_previous("@parameter.inner", "textobjects")
    end, { desc = "TS swap parameter with previous" })

    local function map_move(lhs, method, capture, desc)
      map({ "n", "x", "o" }, lhs, function()
        move[method](capture, "textobjects")
      end, { desc = desc })
    end

    map_move(
      "]m",
      "goto_next_start",
      "@function.outer",
      "TS next function start"
    )
    map_move(
      "]P",
      "goto_next_start",
      "@parameter.outer",
      "TS next parameter start"
    )
    map_move("]M", "goto_next_end", "@function.outer", "TS next function end")
    map_move("]p", "goto_next_end", "@parameter.outer", "TS next parameter end")
    map_move(
      "[m",
      "goto_previous_start",
      "@function.outer",
      "TS prev function start"
    )
    map_move(
      "[P",
      "goto_previous_start",
      "@parameter.outer",
      "TS prev parameter start"
    )
    map_move(
      "[M",
      "goto_previous_end",
      "@function.outer",
      "TS prev function end"
    )
    map_move(
      "[p",
      "goto_previous_end",
      "@parameter.outer",
      "TS prev parameter end"
    )
  end,
})
