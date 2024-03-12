{pkgs, ...}: {
  plugins = {
    rustaceanvim = {
      enable = true;

      # Configuration for rust-analyzer itself
      # Taken from: https://github.com/traxys/Nixfiles/blob/master/neovim/default.nix
      server = {
        settings = {
          cargo.features = "all";
          checkOnSave = true;
          check.command = "clippy";
          rustc.source = "discover";
          inlayHints = {
            lifetimeElisionHints = {
              enable = "always";
              useParameterNames = true;
            };
          };
        };
      };

      tools = {
        executor = "toggleterm";
        onInitialized = ''
          function()
          	vim.notify("successfully initialised rust-analyzer")
          end
        '';
      };
      extraOptions = {
        auto_focus = true;
      };
    };

    # Define the keymaps to which-key
    which-key = {
      registrations = {
        "<leader>a" = "Rust action";
        "<leader>fr" = {
          name = "+Rust";
          r = "Find Rust runnables";
          t = "Find Rust testables";
          d = "Find Rust debuggables";
          a = "Run last Rust test";
        };
      };
    };

    # Completion for crates in Cargo.toml, as well as some other
    # relevant UI stuff
    crates-nvim.enable = true;
  };

  extraPlugins = with pkgs.vimPlugins; [
    rust-vim
    neotest
  ];

  keymaps = [
    {
      action = ''
        function()
        	vim.cmd.RustLsp('codeAction')
        end
      '';
      key = "<leader>a";
      mode = "n";
      options = {
        desc = "Rust action";
        silent = true;
      };
    }
    {
      action = ":RustLsp runnables<CR>";
      key = "<leader>frr";
      mode = "n";
      options = {
        desc = "Find Rust runnables";
        silent = true;
      };
    }
    {
      action = ":RustLsp testables<CR>";
      key = "<leader>frt";
      mode = "n";
      options = {
        desc = "Find Rust testables";
        silent = true;
      };
    }
    {
      action = ":RustLsp debuggables<CR>";
      key = "<leader>frd";
      mode = "n";
      options = {
        desc = "Find Rust debuggables";
        silent = true;
      };
    }
    {
      action = ":RustLsp testables last<CR>";
      key = "<leader>fra";
      mode = "n";
      options = {
        desc = "Run last Rust test";
        silent = true;
      };
    }
  ];

  extraConfigLua = ''
    require("neotest").setup({
    	adapters = {
    		require('rustaceanvim.neotest')
    	}
    })
  '';
}
