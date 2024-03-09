/*
* Lualine is a status line for Neovim. It is the line at the bottom of the window
* that displays information such as the current mode, file name, active language
* servers, diagnostics, etc.
*/
{
  plugins.lualine = {
    enable = true;
    alwaysDivideMiddle = true;
    globalstatus = true;
    ignoreFocus = ["neo-tree"];
    extensions = ["fzf"];
    theme = "auto";
    componentSeparators = {
      left = "|";
      right = "|";
    };
    sectionSeparators = {
      left = "█"; # 
      right = "█"; # 
    };
    sections = {
      lualine_a = ["mode"];
      lualine_b = [
        {
          name = "branch";
          icon = "";
        }
        "diff"
        "diagnostics"
      ];
      lualine_c = ["filename"];
      lualine_x = ["filetype"];
      lualine_y = ["progress"];
      lualine_z = [''" " .. os.date("%R")''];
    };
  };
}
