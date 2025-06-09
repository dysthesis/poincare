vim.diagnostic.config {
  virtual_text = {
    format = function(diagnostic)
      local client = vim.lsp.get_client_by_id(diagnostic.source)
      local prefix = ''
      if client and client.name then
        prefix = client.name .. ': '
      elseif diagnostic.source then
        prefix = diagnostic.source .. ': '
      end
      return prefix .. diagnostic.message
    end,
  },

  virtual_lines = { current_line = true },

  underline = true,

  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '󰅚 ',
      [vim.diagnostic.severity.WARN] = '󰀪 ',
      [vim.diagnostic.severity.INFO] = '󰋽 ',
      [vim.diagnostic.severity.HINT] = '󰌶 ',
    },

    numhl = {
      [vim.diagnostic.severity.ERROR] = 'ErrorMsg',
      [vim.diagnostic.severity.WARN] = 'WarningMsg',
    },
  },
  update_in_insert = false,
  severity_sort = true,
}

-- NOTE: Define LSPs to enable here
local lsps = {
  'luals',
  'tinymist',
  'rust-analyzer',
}

for _, lsp in ipairs(lsps) do
  vim.lsp.enable(lsp)
end

vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
    end
    local opts = { buffer = event.buf }

    require('lz.n').trigger_load('mini.pick')
    -- Display documentation of the symbol under the cursor
    vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)

    -- Jump to the definition
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)

    -- Format current file
    vim.keymap.set({ 'n', 'x' }, 'gq', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)

    -- Displays a function's signature information
    vim.keymap.set('i', '<C-s>', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)

    -- Jump to declaration
    vim.keymap.set('n', '<leader>cd', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)

    -- Lists all the implementations for the symbol under the cursor
    vim.keymap.set('n', '<leader>ci', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)

    -- Jumps to the definition of the type symbol
    vim.keymap.set('n', '<leader>ct', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)

    -- Lists all the references
    vim.keymap.set('n', '<leader>cR', '<cmd>lua vim.lsp.buf.references()<cr>', opts)

    -- Selects a code action available at the current cursor position
    vim.keymap.set('n', '<leader>ca', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
  end,
})
