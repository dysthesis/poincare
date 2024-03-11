{
  plugins = {
    cmp = {
      enable = true;

      settings = {
        snippet.expand = "luasnip";

        # Show a preview of nvim-cmp's autocompletion as 'ghost text'
        experimental = {
          ghost_text = true;
        };

        mapping = {
          "<Return>" = "cmp.mapping.confirm({ select = true }, {'i', 's'})";
          "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
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

        formatting = {
          fields = ["kind" "abbr" "menu"];
          expandableIndicator = true;
        };

        window = {
          completion = {
            border = "rounded";
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None";
          };
          documentation = {
            border = "rounded";
          };
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
