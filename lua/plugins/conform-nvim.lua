-- Formatter
require('lz.n').load {
  'conform.nvim',
  event = 'BufWritePre',
  after = function()
    require('conform').setup {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Disable "format_on_save lsp_fallback" for languages that don't
        -- have a well standardized coding style. You can add additional
        -- languages here or re-enable it for the disabled ones.
        local disable_filetypes = {}
        return {
          timeout_ms = 500,
          lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
        }
      end,
      format_after_save = {
        async = true,
      },
      formatters_by_ft = (function()
        local function formatters_if_available(entries)
          local result = {}
          for _, entry in ipairs(entries) do
            local formatter = entry[1]
            local cmd = entry[2] or formatter
            if vim.fn.executable(cmd) == 1 then
              table.insert(result, formatter)
            end
          end
          return result
        end

        local by_ft = {
          lua = formatters_if_available { { 'stylua' } },
          markdown = formatters_if_available { { 'markdownlint' } },
          nix = formatters_if_available { { 'alejandra' } },
          c = formatters_if_available { { 'clang-format' } },
          rust = formatters_if_available { { 'rustfmt' } },
          go = formatters_if_available { { 'go/fmt', 'gofmt' } },
        }

        for ft, formatters in pairs(by_ft) do
          if #formatters == 0 then
            by_ft[ft] = nil
          end
        end

        return by_ft
      end)(),
    }
  end,
}
