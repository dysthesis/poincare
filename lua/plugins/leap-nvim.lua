-- Leap lazy loads itself
require('leap').leap { backward = true }
-- If using the default mappings (`gs` for multi-window mode), you can
-- map e.g. `gS` here.
vim.keymap.set({ 'n', 'x', 'o' }, 'gs', function()
  require('leap.remote').action()
end)
