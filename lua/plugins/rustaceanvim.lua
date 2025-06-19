---@return rustaceanvim.Opts
vim.g.rustaceanvim = function()
  local bufnr = vim.api.nvim_get_current_buf()
  ---@type rustaceanvim.Opts
  local rustacean_opts = {
    server = {
      default_settings = {
        ['rust-analyzer'] = {
          cargo = {
            loadOutDirsFromCheck = true,
            runBuildScripts = true,
          },
          procMacro = {
            enable = true,
          },
          inlayHints = {
            lifetimeElisionHints = {
              enable = true,
              useParameterNames = true,
            },
          },
        },
      },
    },
    dap = {
      adapter = require('rustaceanvim.config').get_codelldb_adapter(vim.g.codelldb_path, vim.g.liblldb_path),
    },
  }
  vim.keymap.set(
    'n',
    'K', -- Override Neovim's built-in hover keymap with rustaceanvim's hover actions
    function()
      vim.cmd.RustLsp { 'hover', 'actions' }
    end,
    { silent = true, buffer = bufnr }
  )

  vim.keymap.set('n', '<leader>dc', function()
    vim.cmd.RustLsp('debuggables')
  end, { silent = true, buffer = bufnr })

  vim.keymap.set('n', '<leader>dr', function()
    vim.cmd.RustLsp('renderDiagnostic')
  end, { silent = true, buffer = bufnr })

  vim.keymap.set('n', '<leader>de', function()
    vim.cmd.RustLsp('explainError')
  end, { silent = true, buffer = bufnr })
  return rustacean_opts
end
