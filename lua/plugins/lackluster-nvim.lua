require('lackluster').setup {
  tweak_background = {
    normal = 'none',
    telescope = 'none', -- telescope
    menu = 'none', -- nvim_cmp, wildmenu ... (bad idea to transparent)
    popup = 'none',
  },
}
vim.cmd.colorscheme('lackluster-night')
