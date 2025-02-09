-- Save effort from having to generate keys for each mark
local function generate_keys(num_marks)
  local keys = {
    { -- Mark current file
      '<leader>H',
      function()
        require('harpoon'):list():add()
      end,
      desc = '[H]arpoon File',
    },
    { -- Open a list of marked files
      '<leader>hl',
      function()
        local harpoon = require('harpoon')
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end,
      desc = '[H]arpoon [L]ist (Quick)',
    },
  }

  -- Add keys for up to `num_marks` marks
  for i = 1, num_marks do
    table.insert(keys, {
      '<leader>' .. i,
      function()
        require('harpoon'):list():select(i)
      end,
      desc = 'Harpoon to file [' .. i .. ']',
    })
  end
  return keys
end

require('lz.n').load {
  'harpoon',
  keys = generate_keys(9),
  after = function()
    require('harpoon'):setup()
  end,
}
