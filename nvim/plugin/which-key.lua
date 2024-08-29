local wk = require('which-key')

wk.setup {
  preset = 'helix',
}

wk.add {
  { '<leader>n', group = '[N]ote', icon = { icon = ' ', color = 'purple' } },
  { '<leader>c', group = '[C]ode', icon = { icon = ' ', color = 'blue' } },
  { '<leader>f', group = '[F]ind', icon = { icon = ' ', color = 'cyan' } },
  { '<leader>G', group = '[G]it', icon = { icon = ' ', color = 'red' } },
  { '<leader>h', group = '[H]arpoon', icon = { icon = '󱡀 ', color = 'azure' } },
  { '<leader>s', group = '[S]how', icon = { icon = ' ', color = 'yellow' } },
  { '<leader>t', group = '[T]oggle', icon = { icon = ' ', color = 'green' } },
  { '<leader>d', group = '[D]ebug', icon = { icon = ' ', color = 'orange' } },
}
