require('lz.n').load {
  'nvim-lspconfig',

  event = { 'BufReadPre', 'BufNewFile' },

  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('mini.completion')
  end,

  after = function()
    local lspconfig = require('lspconfig')

    local signs = {
      Error = '󰅚 ',
      Warn = ' ',
      Info = ' ',
      Hint = '󰌶 ',
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
    capabilities = vim.tbl_deep_extend('force', capabilities, require('blink.cmp').get_lsp_capabilities())

    local servers = {
      clangd = {
        filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
        keys = {
          { '<leader>cR', '<cmd>ClangdSwitchSourceHeader<cr>', desc = 'Switch Source/Header (C/C++)' },
        },

        root_dir = function(fname)
          return require('lspconfig.util').root_pattern(
            '.clangd',
            '.clang-tidy',
            '.clang-format',
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
          '--j=12',
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

      basedpyright = {},
      tsserver = {},
      texlab = {},
      nixd = {
        nixpkgs = {
          expr = 'import <nixpkgs> { }',
        },
        formatting = {
          command = { 'nixfmt' },
        },
      },

      lua_ls = {
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

    for name, config in pairs(servers) do
      config.capabilities = vim.tbl_deep_extend('force', {}, capabilities, config.capabilities or {})
      lspconfig[name].setup(config)
    end
  end,
}
