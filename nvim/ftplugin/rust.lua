-- Load neotest module
require('lz.n').load {
  'rustaceanvim',
  ft = 'rust',
  after = function()
    -- Configure rustaceanvim here
    vim.g.rustaceanvim = {
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
        -- cmd = { "rustup", "run", "stable", "rust-analyzer" },
        cmd = { '/usr/bin/rust-analyzer' },
      },
      -- DAP configuration
      dap = {},
    }
  end,
}

local neotest_loaded, neotest = pcall(require, 'neotest')

if neotest_loaded then
  neotest.setup {
    adapters = {
      require('rustaceanvim.neotest'),
    },
  }
end
