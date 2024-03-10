/*
* Lualine is a status line for Neovim. It is the line at the bottom of the window
* that displays information such as the current mode, file name, active language
* servers, diagnostics, etc.
*/
{
  plugins.lualine = {
    enable = true;
    extensions = [
      "fzf"
      "nvim-dap-ui"
      "symbols-outline"
      "trouble"
      "neo-tree"
      "quickfix"
      "fugitive"
    ];

    componentSeparators = {
      left = "|";
      right = "|";
    };

    sections = {
      lualine_a = ["mode"];
      lualine_b = ["branch" "filename"];
      lualine_c = ["diff" "diagnostics"];
      lualine_x = ["encoding" "fileformat" "filetype"];
      lualine_y = ["progress"];
      lualine_z = ["location"];
    };

    inactiveSections = {
      lualine_a = ["filename"];
      lualine_b = [];
      lualine_c = ["diagnostics"];
      lualine_x = [];
      lualine_y = [];
      lualine_z = ["location"];
    };
  };
}
