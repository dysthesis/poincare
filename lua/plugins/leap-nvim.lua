-- Leap lazy loads itself
require('leap').create_default_mappings()
-- If using the default mappings (`gs` for multi-window mode), you can
-- map e.g. `gS` here.
vim.keymap.set({ 'n', 'x', 'o' }, 'gs', function()
  require('leap.remote').action()
end)
