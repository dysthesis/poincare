vim.g.rustaceanvim = function()
  local codelldb_path = vim.g.codelldb_path .. 'adapter/codelldb'
  local liblldb_path = vim.g.codelldb_path .. 'lldb/lib/liblldb'
  local cfg = require('rustaceanvim.config')

  return {
    tools = {
      hover_actions = { auto_focus = true },
      test_executor = 'neotest',
    },
    server = {
      on_attach = function(_, b)
        vim.lsp.inlay_hint.enable(true, { bufnr = b })
      end,
      settings = {
        ['rust-analyzer'] = {
          cargo = { features = 'all' },

          assist = {
            importEnforceGranularity = true,
            importPrefix = 'crate',
          },

          checkOnSave = {
            enable = true,
            command = 'clippy',
            features = 'all',
          },

          inlayHints = {
            chainingHints = {
              bindingModeHints = {
                enable = true,
              },

              chainingHints = {
                enable = true,
              },

              closingBraceHints = {
                enable = true,
                minLines = 25,
              },

              closureCaptureHints = {
                enable = true,
              },

              closureReturnTypeHints = {
                enable = 'always', -- "never"
              },

              closureStyle = 'impl_fn',

              discriminantHints = {
                enable = 'always', -- "never"
              },

              expressionAdjustmentHints = {
                hideOutsideUnsafe = false,
                mode = 'prefix',
              },

              implicitDrops = {
                enable = true,
              },

              lifetimeElisionHints = {
                enable = 'always', -- "never"
                useParameterNames = true,
              },

              maxLength = 25,

              parameterHints = {
                enable = true,
              },

              rangeExclusiveHints = {
                enable = true,
              },

              renderColons = {
                enable = true,
              },

              typeHints = {
                enable = true,
                hideClosureInitialization = false,
                hideNamedConstructor = false,
              },
            },
          },

          lens = {
            enable = true,
          },
        },
      },

      standalone = true,
    },
    dap = {
      adapter = cfg.get_codelldb_adapter(codelldb_path, liblldb_path),
    },
  }
end
require('lz.n').load {
  'rustaceanvim',
  ft = 'rust',
}
