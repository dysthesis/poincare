require('lz.n').load {
  'telescope.nvim',
  cmd = 'Telescope',
  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('telescope-ui-select.nvim')
    vim.cmd.packadd('telescope-fzf-native.nvim')
  end,
  keys = {
    -- Searching
    { '<leader>fb', '<cmd>Telescope buffers<cr>', desc = '[F]ind [B]uffers' },
    { '<leader>fc', '<cmd>Telescope command_history<cr>', desc = '[F]ind [C]ommand history' },
    { '<leader>fC', '<cmd>Telescope commands<cr>', desc = '[F]ind available [C]ommands' },
    { '<leader>ff', '<cmd>Telescope find_files<cr>', desc = '[F]ind [F]iles' },
    { '<leader>fh', '<cmd>Telescope help_tags<cr>', desc = '[F]ind [H]elp' },
    { '<leader>fg', '<cmd>Telescope live_grep<cr>', desc = '[F]ind [G]rep' },
  },
  after = function()
    require('telescope').setup {
      extensions = {
        fzf = {
          fuzzy = true, -- false will only do exact matching
          override_generic_sorter = true, -- override the generic sorter
          override_file_sorter = true, -- override the file sorter
          case_mode = 'smart_case', -- or "ignore_case" or "respect_case"
          -- the default case_mode is "smart_case"
        },
      },
    }
    require('telescope').load_extension('fzf')
    require('telescope').load_extension('ui-select')
  end,
}
