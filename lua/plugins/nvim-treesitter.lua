if vim.g.did_load_treesitter_plugin then
  return
end
vim.g.did_load_treesitter_plugin = true

local configs = require('nvim-treesitter.configs')
vim.g.skip_ts_context_comment_string_module = true

---@diagnostic disable-next-line: missing-fields
configs.setup {
  -- ensure_installed = "all", -- causes a ~30ms increase in startup time
  -- auto_install = true, -- Do not automatically install missing parsers when entering buffer
  highlight = {
    enable = true,
    disable = { 'latex' },
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = '<cr>',
      node_incremental = '<cr>',
      scope_incremental = false,
      node_decremental = '<s-tab>',
    },
  },
  textobjects = {
    select = {
      enable = true,
      -- Automatically jump forward to textobject, similar to targets.vim
      lookahead = true,
      keymaps = {
        ['af'] = '@function.outer',
        ['if'] = '@function.inner',
        ['ac'] = '@class.outer',
        ['ic'] = '@class.inner',
        ['aC'] = '@call.outer',
        ['iC'] = '@call.inner',
        ['a#'] = '@comment.outer',
        ['i#'] = '@comment.outer',
        ['ai'] = '@conditional.outer',
        ['ii'] = '@conditional.outer',
        ['al'] = '@loop.outer',
        ['il'] = '@loop.inner',
        ['aP'] = '@parameter.outer',
        ['iP'] = '@parameter.inner',
      },
      selection_modes = {
        ['@parameter.outer'] = 'v', -- charwise
        ['@function.outer'] = 'V', -- linewise
        ['@class.outer'] = '<c-v>', -- blockwise
      },
    },
    swap = {
      enable = true,
      swap_next = {
        ['<leader>a'] = '@parameter.inner',
      },
      swap_previous = {
        ['<leader>A'] = '@parameter.inner',
      },
    },
    move = {
      enable = true,
      set_jumps = true, -- whether to set jumps in the jumplist
      goto_next_start = {
        [']m'] = '@function.outer',
        [']P'] = '@parameter.outer',
      },
      goto_next_end = {
        [']m'] = '@function.outer',
        [']P'] = '@parameter.outer',
      },
      goto_previous_start = {
        ['[m'] = '@function.outer',
        ['[P'] = '@parameter.outer',
      },
      goto_previous_end = {
        ['[m'] = '@function.outer',
        ['[P'] = '@parameter.outer',
      },
    },
    nsp_interop = {
      enable = true,
      peek_definition_code = {
        ['df'] = '@function.outer',
        ['dF'] = '@class.outer',
      },
    },
  },
}

-- Tree-sitter based folding
vim.filetype.add {
  pattern = { ['.*/hypr/.*%.conf'] = 'hyprlang' },
}
if vim.fn.has('nvim-0.10') == 1 then
  vim.opt.foldexpr = "v:lua.require'utils.folding'.foldexpr()"
  vim.opt.foldmethod = 'expr'
end
