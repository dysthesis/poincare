require('lz.n').load {
  'nvim-lint',
  event = { 'BufReadPre', 'BufNewFile' },
  after = function()
    local lint = require('lint')
    lint.linters.zlint = {
      cmd = 'zlint',
      stdin = false,
      append_fname = false,
      args = { '-f', 'gh' },
      stream = 'both',
      ignore_exitcode = true,
      parser = function(output, bufnr)
        local items = {}
        -- get buffer by file name
        for line in vim.gsplit(output, '\n') do
          local level, file, row, col, message = line:match('::(%w+)%sfile=([^,]+),line=(%d+),col=(%d+),title=(.*)')
          local severity = nil
          -- map linter levels to diagnostic levels
          -- zlint levels: error, warning, off
          if level == 'error' then
            severity = vim.diagnostic.severity.ERROR
          elseif level == 'warning' then
            severity = vim.diagnostic.severity.WARN
          end

          if file and severity then
            local l_bufnr = vim.fn.bufnr(file)
            if l_bufnr > -1 and l_bufnr == bufnr then
              table.insert(items, {
                lnum = tonumber(row) - 1,
                col = tonumber(col) - 1,
                message = message,
                source = 'zlint',
                bufnr = bufnr,
                severity = severity,
              })
            end
          end
        end

        return items
      end,
    }
    local function linters_if_available(entries)
      local result = {}
      for _, entry in ipairs(entries) do
        local linter = entry[1]
        local cmd = entry[2] or linter
        if vim.fn.executable(cmd) == 1 then
          table.insert(result, linter)
        end
      end
      return result
    end

    local by_ft = {
      zig = linters_if_available { { 'zlint' } },
      rust = linters_if_available { { 'clippy', 'cargo' } },
      nix = linters_if_available { { 'statix' } },
      markdown = linters_if_available { { 'vale' } },
    }

    for ft, linters in pairs(by_ft) do
      if #linters == 0 then
        by_ft[ft] = nil
      end
    end

    lint.linters_by_ft = by_ft
    local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      group = lint_augroup,
      callback = function()
        -- Only run the linter in buffers that you can modify in order to
        -- avoid superfluous noise, notably within the handy LSP pop-ups that
        -- describe the hovered symbol using Markdown.
        if vim.opt_local.modifiable:get() then
          lint.try_lint()
        end
      end,
    })
  end,
}
