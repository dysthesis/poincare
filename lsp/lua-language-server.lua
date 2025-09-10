return {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.luarc.jsonc' },
  settings = {
    Lua = {
      workspace = {
        library = vim.api.nvim_get_runtime_file('', true),
        -- library = {
        --   [vim.fn.stdpath('config') .. '/lua'] = true,
        --   [vim.fn.expand('$VIMRUNTIME/lua')] = true,
        --   [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true,
        --   [plugins_path .. '/nvim-lua/plenary.nvim/lua'] = true,
        --   [plugins_path] = true,
        -- },
      },
    },
  },
}
