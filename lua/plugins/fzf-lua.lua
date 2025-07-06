require('lz.n').load {
  'fzf-lua',
  cmd = 'FzfLua',
  keys = {
    {
      '<leader>f',
      function()
        require('fzf-lua').files()
      end,
      desc = 'Find [F]iles',
    },
    {
      '<leader>g',
      function()
        require('fzf-lua').live_grep_native()
      end,
      desc = 'Find [G]rep',
    },
    {
      'gR',
      function()
        require('fzf-lua').lsp_references()
      end,
      desc = 'Find [R]eferences',
    },
    {
      'gD',
      function()
        require('fzf-lua').lsp_definitions()
      end,
      desc = 'Find [D]efinitions',
    },
    {
      'gY',
      function()
        require('fzf-lua').lsp_typedefs()
      end,
      desc = 'Find t[Y]pe definitions',
    },
    {
      'gM',
      function()
        require('fzf-lua').lsp_implementations()
      end,
      desc = 'Find t[Y]pe definitions',
    },
    {
      '<leader>s',
      function()
        require('fzf-lua').lsp_document_symbols()
      end,
      desc = 'Find [S]ymbols',
    },
    {
      '<leader>S',
      function()
        require('fzf-lua').lsp_live_workspace_symbols()
      end,
      desc = 'Find Workspace [S]ymbols',
    },
    {
      '<leader>d',
      function()
        require('fzf-lua').diagnostics_workspace()
      end,
      desc = 'Find Workspace [D]iagnostics',
    },
    {
      '<leader>DB',
      function()
        require('fzf-lua').dap_breakpoints()
      end,
      desc = 'Find [D]AP [B]reakpoints',
    },
    {
      '<leader>Dv',
      function()
        require('fzf-lua').dap_variables()
      end,
      desc = 'Find [D]AP [V]ariables',
    },
    {
      '<leader>Df',
      function()
        require('fzf-lua').dap_frames()
      end,
      desc = 'Find [D]AP [F]rames',
    },
  },
  after = function()
    require('fzf-lua').register_ui_select()
  end,
}
