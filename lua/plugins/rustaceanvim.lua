---@return rustaceanvim.Opts
vim.g.rustaceanvim = function()
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
  return rustacean_opts
end
