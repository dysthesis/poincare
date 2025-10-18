-- Bootstrap the package manager
local function clone_paq()
  local path = vim.fn.stdpath('data') .. '/site/pack/paqs/start/paq-nvim'
  local is_installed = vim.fn.empty(vim.fn.glob(path)) == 0
  if not is_installed then
    vim.fn.system { 'git', 'clone', '--depth=1', 'https://github.com/savq/paq-nvim.git', path }
    return true
  end
end

local function bootstrap_paq(packages)
  local first_install = clone_paq()
  vim.cmd.packadd('paq-nvim')
  local paq = require('paq')
  if first_install then
    vim.notify('Installing plugins... If prompted, hit Enter to continue.')
  end

  -- Read and install packages
  paq(packages)
  paq.install()
end

-- Add plugins here
-- TODO: Sort this
local plugins = {
  'savq/paq-nvim', -- the package manager itself

  -- Folding
  'kevinhwang91/nvim-ufo',
  'kevinhwang91/promise-async',

  -- Completion
  { -- supposedly faster than nvim-cmp
    'saghen/blink.cmp',
    build = 'cargo build --locked --release --target-dir target',
    version = '*',
  },
  'saghen/blink.compat', -- compatibility layer
  -- "echasnovski/mini.completion", -- does not support snippets yet
  'rafamadriz/friendly-snippets',

  { 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' }, -- tree sitter integration
  'nvim-treesitter/nvim-treesitter-textobjects',
  'stevearc/conform.nvim',

  'folke/todo-comments.nvim',
  { 'ThePrimeagen/harpoon', branch = 'harpoon2' }, -- tree sitter integration

  -- Language extensions
  -- Rust
  'saecki/crates.nvim', -- rust crates

  -- LaTeX
  'lervag/vimtex',
  'jbyuki/nabla.nvim',

  -- Notetaking
  'zk-org/zk-nvim',

  'ggandor/leap.nvim',

  -- Themes
  'slugbyte/lackluster.nvim',
  -- "kdheepak/monochrome.nvim",
  -- "killitar/obscure.nvim",
  -- "jesseleite/nvim-noirbuddy",
  -- "tjdevries/colorbuddy.nvim",

  'echasnovski/mini.pick', -- a fuzzy finder
  'echasnovski/mini.surround', -- add a surround motion
  'echasnovski/mini.icons', -- icons library
  'echasnovski/mini.ai', -- more a/i textobjects
  'echasnovski/mini.indentscope', -- visualise and operate om indent scope
  'nvim-neorocks/lz.n', -- a lazy loader
  'sindrets/diffview.nvim', -- a nice diff viewing ui
  'lewis6991/gitsigns.nvim', -- some nice git integration
  'stevearc/oil.nvim',

  'altermo/ultimate-autopair.nvim',
  'christoomey/vim-tmux-navigator',
  'nvim-lua/plenary.nvim',
}

-- Call helper function
bootstrap_paq(plugins)

vim.g.codelldb_path = '~/.local/share/codelldb'

-- Load plugin configurations, if they exist
-- local num = 0
for _, plugin in ipairs(plugins) do
  -- num = num + 1
  local name = ''
  if type(plugin) == 'table' then
    name = plugin[1]
  else
    name = plugin
  end
  name = name:match('.*/(.*)'):gsub('%.', '-') or ''

  local formatted = 'plugins.' .. name
  -- Load the configuration only if it exists
  local ok, _ = pcall(require, formatted)
end
-- vim.notify("Loaded " .. num .. " plugins")
