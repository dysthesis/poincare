local fmt_by_ft = {
  nix = function(buf)
    return { 'alejandra', '-qq', vim.api.nvim_buf_get_name(buf) }
  end,
  lua = function(buf)
    return { 'stylua', vim.api.nvim_buf_get_name(buf) }
  end,
  sh = function(buf)
    return { 'shfmt', '-w', '-i', '2', '-ci', vim.api.nvim_buf_get_name(buf) }
  end,
  rust = function()
    return { 'cargo', 'fmt' }
  end,
}

local group = vim.api.nvim_create_augroup('AutoFormat', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  pattern = '*',
  callback = function(args)
    local ft = vim.bo[args.buf].filetype
    local make = fmt_by_ft[ft]
    if not make then
      return
    end
    vim.system(
      make(args.buf),
      { text = true },
      vim.schedule_wrap(function(res)
        if res.code == 0 then
          vim.cmd('silent checktime ' .. args.buf)
        else
          vim.notify('Formatter failed with code: ' .. res.code, vim.log.levels.WARN)
        end
      end)
    )
  end,
})
