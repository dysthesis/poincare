{
  plugins = {
    nvim-cmp = {
      enable = true;
      experimental = {
        ghost_text = true;
      };
      formatting = {
        fields = ["kind" "abbr" "menu"];
        expandableIndicator = true;
      };
      snippet.expand = "luasnip";
      mappingPresets = ["insert"];
      window = {
        completion = {
          border = "rounded";
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None";
        };
        documentation = {
          border = "rounded";
        };
      };
      sources = [
        {
          name = "nvim_lsp";
          groupIndex = 1;
          priority = 3;
        }
        {
          name = "luasnip";
          option = {
            show_autosnippets = true;
          };
          groupIndex = 1;
          priority = 5;
        }
        {
          name = "path";
          groupIndex = 1;
        }
        {
          name = "buffer";
          groupIndex = 2;
          priority = 2;
        }
      ];
      mapping = {
        "<Return>" = {
          modes = ["i" "s"];
          action = "cmp.mapping.confirm({ select = true })";
        };
      };
    };
    lspkind = {
      enable = true;
    };
    cmp-nvim-lsp = {enable = true;}; # lsp
    cmp-buffer = {enable = true;};
    cmp-path = {enable = true;}; # file system paths
    cmp_luasnip = {enable = true;}; # snippets
    cmp-cmdline = {enable = true;}; # autocomplete for cmdline
  };
  extraConfigLua = ''
      kind_icons = {
        Text = "󰊄",
        Method = "",
        Function = "󰡱",
        Constructor = "",
        Field = "",
        Variable = "󱀍",
        Class = "",
        Interface = "",
        Module = "󰕳",
        Property = "",
        Unit = "",
        Value = "",
        Enum = "",
        Keyword = "",
        Snippet = "",
        Color = "",
        File = "",
        Reference = "",
        Folder = "",
        EnumMember = "",
        Constant = "",
        Struct = "",
        Event = "",
        Operator = "",
        TypeParameter = "",
      } 

    local cmp = require'cmp'

      -- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline({'/', "?" }, {
          sources = {
          { name = 'buffer' }
          }
          })

    -- Set configuration for specific filetype.
      cmp.setup.filetype('gitcommit', {
          sources = cmp.config.sources({
              { name = 'cmp_git' }, -- You can specify the `cmp_git` source if you were installed it.
              }, {
              { name = 'buffer' },
              })
          })

    -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline(':', {
          sources = cmp.config.sources({
              { name = 'path' }
              }, {
              { name = 'cmdline' }
              }),
          })  '';
}
