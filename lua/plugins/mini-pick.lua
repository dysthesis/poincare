require('lz.n').load {
  'mini.pick',
  cmd = 'Pick',
  keys = {
    {
      '<leader>f',
      function()
        require('mini.pick').builtin.files()
      end,
      desc = 'Find [F]iles',
    },
    {
      '<leader>/',
      function()
        require('mini.pick').builtin.grep_live()
      end,
      desc = 'Find [G]rep',
    },
    {
      '<leader>l',
      function()
        require('mini.pick').registry.buffer_lines_current()
      end,
      desc = 'Find buffer [L]ines',
    },
    {
      '<leader>d',
      function()
        require('mini.extra').pickers.diagnostic()
      end,
      desc = 'Find [D]iagnostics',
    },
    {
      '<leader>e',
      function()
        require('mini.extra').pickers.explorer()
      end,
      desc = 'Find [D]iagnostics',
    },
    {
      '<leader>g',
      function()
        require('mini.extra').pickers.git_commits()
      end,
      desc = 'Find [G]it commits',
    },
    {
      '<leader>G',
      function()
        require('mini.extra').pickers.git_branches()
      end,
      desc = 'Find [G]it branches',
    },
    {
      '<leader>s',
      function()
        require('mini.extra').pickers.lsp { scope = 'document_symbol' }
      end,
      desc = 'Find [S]ymbols',
    },
    {
      '<leader>S',
      function()
        require('mini.extra').pickers.lsp { scope = 'workspace_symbol' }
      end,
      desc = 'Find Workspace [S]ymbols',
    },
    {
      '<leader>r',
      function()
        require('mini.extra').pickers.lsp { scope = 'references' }
      end,
      desc = 'Find [R]eferences',
    },
    {
      '<leader>i',
      function()
        require('mini.extra').pickers.lsp { scope = 'implementation' }
      end,
      desc = 'Find [I]mplementation',
    },
    {
      '<leader>T',
      function()
        require('mini.extra').pickers.treesitter()
      end,
      desc = 'Find [T]reesitter nodes',
    },
  },
  after = function()
    local MiniPick = require('mini.pick')
    local MiniExtra = require('mini.extra')

    local ns_digit_prefix = vim.api.nvim_create_namespace('cur-buf-pick-show')
    local show_cur_buf_lines = function(buf_id, items, query, opts)
      if items == nil or #items == 0 then
        return
      end

      -- Show as usual
      MiniPick.default_show(buf_id, items, query, opts)

      -- Move prefix line numbers into inline extmarks
      local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
      local digit_prefixes = {}
      for i, l in ipairs(lines) do
        local _, prefix_end, prefix = l:find('^(%s*%d+│)')
        if prefix_end ~= nil then
          digit_prefixes[i], lines[i] = prefix, l:sub(prefix_end + 1)
        end
      end

      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
      for i, pref in pairs(digit_prefixes) do
        local opts = { virt_text = { { pref, 'MiniPickNormal' } }, virt_text_pos = 'inline' }
        vim.api.nvim_buf_set_extmark(buf_id, ns_digit_prefix, i - 1, 0, opts)
      end

      -- Set highlighting based on the curent filetype
      local ft = vim.bo[items[1].bufnr].filetype
      local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
      local has_ts, _ = pcall(vim.treesitter.start, buf_id, has_lang and lang or ft)
      if not has_ts and ft then
        vim.bo[buf_id].syntax = ft
      end
    end

    MiniPick.registry.buffer_lines_current = function()
      -- local local_opts = { scope = "current", preserve_order = true } -- use preserve_order
      local local_opts = { scope = 'current' }
      MiniExtra.pickers.buf_lines(local_opts, { source = { show = show_cur_buf_lines } })
    end

    MiniPick.setup {
      options = {
        use_cache = true,
      },
      mappings = {
        move_down = '<C-j>',
        move_up = '<C-k>',
      },
      window = {
        prompt_prefix = '   ',
        config = function()
          -- centered on screen
          local height = math.floor(0.618 * vim.o.lines)
          local width = math.floor(0.618 * vim.o.columns)
          return {
            anchor = 'NW',
            border = 'rounded',
            height = height,
            width = width,
            row = math.floor(0.5 * (vim.o.lines - height)),
            col = math.floor(0.5 * (vim.o.columns - width)),
          }
        end,
      },
    }

    vim.ui.select = MiniPick.ui_select
  end,
}
