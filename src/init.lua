local wo, g, cmd, opt = vim.wo, vim.g, vim.cmd, vim.o

--- Appearance
g.minimal_transparent = true
cmd.colorscheme("minimal")

opt.conceallevel = 2 -- How much syntax to hide
wo.relativenumber = true
opt.colorcolumn = "80"

--- Development
-- LSP servers
local function enable_lsp(lsp)
    local cfg = vim.lsp.config[lsp]
    local bin = cfg and type(cfg.cmd) == "table" and cfg.cmd[1] or lsp
    if vim.fn.executable(bin) == 1 then
        vim.lsp.enable(lsp)
    end
end

for _, lsp in ipairs({
    "lua-language-server",
    "gopls",
    "rust-analyzer",
    "clangd",
    "nil",
    "basedpyright",
    "ty",
}) do
    enable_lsp(lsp)
end
