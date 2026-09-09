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
