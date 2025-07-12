vim.api.nvim_create_augroup('AutoFormat', { clear = true })

local function register_formatter(ft, cmd)
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = '**.' .. ft,
    group = 'AutoFormat',
    callback = function()
      vim.cmd('silent !' .. cmd)
      vim.cmd('edit')
    end,
  })
end

register_formatter('nix', 'alejandra -qq %')
register_formatter('rs', 'cargo fmt')
register_formatter('lua', 'stylua %')
