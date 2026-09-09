-- Which servers we have configurations for in ../lsp/ that we want to make
-- available?
local servers = {
  "nil",
}

local function enable(lsp)
  local cfg = vim.lsp.config[lsp]
  local bin = cfg and type(cfg.cmd) == "table" and cfg.cmd[1] or lsp
  if vim.fn.executable(bin) then
    vim.lsp.enable(lsp)
  end
end

for _, lsp in ipairs(servers) do
  enable(lsp)
end

-- What should be configured when an LSP is available (e.g. bindings for LSP
-- commands)?
local autocmd = vim.api.nvim_create_autocmd
autocmd("LspAttach", {
  desc = "LSP actions",
  callback = function(event)
    local bufnr = event.buf
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

    local map = vim.keymap.set
    local opts = { buf = bufnr }

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
    end, { buf = bufnr, desc = "Toggle inlay hints" })
  end,
})
