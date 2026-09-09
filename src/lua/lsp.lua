-- This module handles global LSP configurations, i.e. configs that apply to
-- any and all servers and languages. For language-specific behaviour, see
-- `lua/lang/*`.

local autocmd = vim.api.nvim_create_autocmd
autocmd("LspAttach", {
  desc = "LSP actions",
  callback = function(event)
    local bufnr = event.buf
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

    local map = vim.keymap.set
    local opts = { buffer = bufnr }

    -- Pressing "K" while hovering over a symbol opens the hover menu for that
    -- symbol.
    map("n", "K", function()
      vim.lsp.buf.hover({ focusable = true })
    end, opts)

    map("n", "gd", vim.lsp.buf.definition, opts)
    map(
      { "n", "x" },
      "gq",
      "<cmd>lua vim.lsp.buf.format({async = true})<cr>",
      opts
    )
    map("i", "<C-s>", vim.lsp.buf.signature_help, opts)
    map("n", "<leader>cd", vim.lsp.buf.declaration, opts)
    map("n", "<leader>ci", vim.lsp.buf.implementation, opts)
    map("n", "<leader>ct", vim.lsp.buf.type_definition, opts)
    map("n", "<leader>cR", vim.lsp.buf.references, opts)
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    map("n", "<leader>cr", vim.lsp.buf.rename, opts)

    -- Toggle inlay hints such as rust-analyzer's implicit `drop(...)` markers.
    map("n", "<leader>ch", function()
      vim.lsp.inlay_hint.enable(
        not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }),
        { bufnr = bufnr }
      )
    end, { buffer = bufnr, desc = "Toggle inlay hints" })
  end,
})
