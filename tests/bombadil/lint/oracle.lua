local M = {}

function M.setup()
  -- This campaign is testing linting, not rust-analyzer.
  vim.lsp.enable("rust_analyzer", false)

  -- Make the missing-linter-executable case deterministic.
  --
  -- Neovim itself has already started, and this campaign only needs editor
  -- operations after setup, so the empty PATH deliberately makes `cargo`
  -- unavailable to clippy.
  vim.env.PATH = "/tmp/poincare-bombadil/linters/bin"
end

return M
