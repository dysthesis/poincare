{
  plugins = {
    cmp = {
      enable = true;
      autoEnableSources = true;

      settings = {
        snippet.expand = ''
          function(args)
            require('luasnip').lsp_expand(args.body)
          end
        '';

        # Show a preview of nvim-cmp's autocompletion as 'ghost text'
        experimental = {
          ghost_text = true;
        };

        mapping = {
          "<Return>" = "cmp.mapping.confirm({ select = true }, {'i', 's'})";
          "<Tab>" = ''
            cmp.mapping(
              function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                elseif luasnip.expandable() then
                  luasnip.expand()
                elseif luasnip.expand_or_jumpable() then
                  luasnip.expand_or_jump()
                elseif check_backspace() then
                  fallback()
                else
                  fallback()
                end
              end,
              { 'i', 's' }
            )
          '';
        };

        sources = [
          {name = "path";}
          {name = "nvim_lua";}
          {name = "nvim_lsp";}
          {
            name = "luasnip";
            option.show_autosnippets = true;
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
