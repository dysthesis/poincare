vim.opt.termguicolors = true

-- Use the global statusline
vim.opt.laststatus = 3

-- Make line numbers default
vim.opt.number = true
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
vim.opt.relativenumber = true

vim.opt.conceallevel = 2
vim.g.vim_markdown_conceal = 1

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes'

-- Set highlight on search, but clear on pressing <Esc> in normal mode
vim.opt.hlsearch = true

vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- Markdown
local bullet_symbol = '•'

--- Function to update the bullet symbol
---@param symbol string Bullet symbol to use
function SetBulletSymbol(symbol)
  bullet_symbol = symbol
end

--- Function to update extmarks in a buffer
---@param bufnr number buffer to update the extmarks in
---@param ns_id number ID
local function update_extmarks(bufnr, ns_id)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  for lnum, line in ipairs(lines) do
    lnum = lnum - 1
    -- Match bullet points
    if string.match(line, '^%s*[-%*%+] ') then
      local indent = string.match(line, '^%s*')
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, lnum, #indent, {
        end_col = #indent + 1,
        conceal = bullet_symbol,
      })
    end
  end
end

--- Autocommand to update extmarks in markdown
local function setup_extmarks_autocmd()
  local ns_id = vim.api.nvim_create_namespace('MarkdownStyling')
  vim.api.nvim_create_autocmd({ 'BufEnter', 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    pattern = '*.md',
    callback = function(ev)
      update_extmarks(ev.buf, ns_id)
    end,
  })
end

-- Setup the autocommand on Vim startup
vim.api.nvim_create_autocmd('VimEnter', {
  callback = setup_extmarks_autocmd,
})
