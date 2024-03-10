{
  config = {
    options = {
      autoindent = true;
      cursorline = true;
      tabstop = 2;
      shiftwidth = 2;
      linebreak = true;
      mouse = "";
      number = true;
      relativenumber = true;
    };

    extraConfigLua = ''
       local opt = vim.opt
       local g = vim.g
       local o = vim.o
         -- Neovide
       if g.neovide then
         -- Neovide options
         g.neovide_fullscreen = false
         g.neovide_hide_mouse_when_typing = false
         g.neovide_refresh_rate = 165
         g.neovide_cursor_vfx_mode = "ripple"
         g.neovide_cursor_animate_command_line = true
         g.neovide_cursor_animate_in_insert_mode = true
         g.neovide_cursor_vfx_particle_lifetime = 5.0
         g.neovide_cursor_vfx_particle_density = 14.0
         g.neovide_cursor_vfx_particle_speed = 12.0
         g.neovide_transparency = 0.85
         g.neovide_padding_top = 20
         g.neovide_padding_bottom = 20
         g.neovide_padding_left = 20
         g.neovide_padding_right = 20
         -- Neovide Fonts
         o.guifont = "JetBrainsMono Nerd Font:Medium:h10"
      end
    '';
  };
  imports = [
    ./keybinds.nix
  ];
}
