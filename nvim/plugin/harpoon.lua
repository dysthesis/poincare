require('lz.n').load {
  'harpoon',

  keys = function()
    local harpoon = require('harpoon')
    local keys = {
      {
        '<leader>H',
        function()
          harpoon:list():add()
        end,
        desc = 'Add file to [H]arpoon',
      },
      {
        '<leader>hl',
        function()
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        desc = '[H]arpoon [L]ist',
      },
    }

    local num_harpoons = 9

    for i = 1, num_harpoons do
      table.insert(keys, {
        '<leader>' .. i,
        function()
          harpoon:list():select(i)
        end,
        desc = 'Harpoon to file [' .. i .. ']',
      })
    end

    return keys
  end,

  after = function()
    require('harpoon').setup {
      menu = {
        width = vim.api.nvim_win_get_width(0) - 4,
      },
      settings = {
        save_on_toggle = true,
      },
    }
  end,
}
