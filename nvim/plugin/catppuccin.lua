require('catppuccin').setup {
  transparent_background = true,
  color_overrides = { all = {
    text = '#ffffff',
    surface0 = '#181825',
  } },
  custom_highlights = function(colors)
    return {
      ['@markup.math'] = { fg = colors.mauve },
      ['@function.latex'] = { fg = colors.mauve },
      TelescopeSelection = { bg = colors.crust },
    }
  end,
}
vim.cmd.colorscheme('catppuccin')
