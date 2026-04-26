---@type vim.lsp.Config
return {
  filetypes = { 'rust' },
  cmd = { 'rust-analyzer' },
  settings = {
    ['rust-analyzer'] = {
      cargo = { features = 'all' },

      check = {
        command = 'clippy',
        features = 'all',
      },

      checkOnSave = true,

      imports = {
        granularity = {
          enforce = true,
          group = 'crate',
        },
        prefix = 'crate',
      },

      inlayHints = {
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

        renderColons = true,

        typeHints = {
          enable = true,
          hideClosureInitialization = false,
          hideNamedConstructor = false,
        },
      },

      lens = {
        enable = true,
      },
    },
  },
}
