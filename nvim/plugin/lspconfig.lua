require('lz.n').load {
  'nvim-lspconfig',

  event = { 'BufReadPre', 'BufNewFile' },

  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('cmp-nvim-lsp')
    vim.cmd.packadd('lspsaga.nvim')
    vim.cmd.packadd('neodev.nvim')
  end,

  after = function()
    local lspconfig = require('lspconfig')

    local signs = {
      Error = ' ',
      Warn = ' ',
      Info = ' ',
      Hint = ' ',
    }

    for type, icon in pairs(signs) do
      local hl = 'DiagnosticSign' .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
    end

    vim.diagnostic.config {
      signs = true,
      update_in_insert = true,
      underline = true,
      severity_sort = true,

      virtual_text = {
        prefix = '',
        format = function(diagnostic)
          local severity = diagnostic.severity

          local function prefix_diagnostic(prefix, value)
            return string.format(prefix .. ' %s', value.message)
          end

          if severity == vim.diagnostic.severity.ERROR then
            return prefix_diagnostic('󰅚', diagnostic)
          end

          if severity == vim.diagnostic.severity.WARN then
            return prefix_diagnostic('⚠', diagnostic)
          end

          if severity == vim.diagnostic.severity.INFO then
            return prefix_diagnostic('ⓘ', diagnostic)
          end

          if severity == vim.diagnostic.severity.HINT then
            return prefix_diagnostic('󰌶', diagnostic)
          end

          return prefix_diagnostic('●', diagnostic)
        end,
      },
    }

    -- LSP servers and clients are able to communicate to each other what features they support.
    --  By default, Neovim doesn't support everything that is in the LSP specification.
    --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
    --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

    -- Enable the following language servers
    --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
    --
    --  Add any additional override configuration in the following tables. Available keys are:
    --  - cmd (table): Override the default command used to start the server
    --  - filetypes (table): Override the default list of associated filetypes for the server
    --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
    --  - settings (table): Override the default settings passed when initializing the server.
    --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
    local servers = {
      -- clangd = {},
      -- gopls = {},
      -- pyright = {},
      -- rust_analyzer = {},
      -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
      --
      -- Some languages (like typescript) have entire language plugins that can be useful:
      --    https://github.com/pmizio/typescript-tools.nvim
      --
      -- But for many setups, the LSP (`tsserver`) will work just fine
      -- tsserver = {},
      --

      clangd = {
        keys = {
          { '<leader>cR', '<cmd>ClangdSwitchSourceHeader<cr>', desc = 'Switch Source/Header (C/C++)' },
        },

        root_dir = function(fname)
          return require('lspconfig.util').root_pattern(
            'Makefile',
            'configure.ac',
            'configure.in',
            'config.h.in',
            'meson.build',
            'meson_options.txt',
            'build.ninja'
          )(fname) or require('lspconfig.util').root_pattern('compile_commands.json', 'compile_flags.txt')(
            fname
          ) or require('lspconfig.util').find_git_ancestor(fname)
        end,

        capabilities = {
          offsetEncoding = { 'utf-16' },
        },

        cmd = {
          'clangd',
          '--background-index',
          '--clang-tidy',
          '--header-insertion=iwyu',
          '--completion-style=detailed',
          '--function-arg-placeholders',
          '--fallback-style=llvm',
        },

        init_options = {
          usePlaceholders = true,
          completeUnimported = true,
          clangdFileStatus = true,
        },
      },

      lua_ls = {
        -- cmd = {...},
        -- filetypes = { ...},
        -- capabilities = {},
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
            },

            completion = {
              callSnippet = 'Replace',
            },

            telemetry = {
              enable = false,
            },

            hint = {
              enable = true,
            },
          },
        },
      },
    }

    require('lspsaga').setup {
      implement = {
        enable = true,
        sign = true,
        virtual_text = true,
      },
    }

    for name, config in ipairs(servers) do
      lspconfig[name].setup(config)
    end
  end,
}
