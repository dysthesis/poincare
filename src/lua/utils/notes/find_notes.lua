local picker = require("utils.picker.notes")

local sink = function(paths, key)
	local cmd = ({ ["ctrl-v"] = "vsplit" })[key] or "edit"
	local path = paths[#paths]
	if not path then
		return
	end
	local esc = vim.fn.fnameescape(path)
	vim.cmd(string.format("%s %s", cmd, esc))
end

local extra = ' --accept-nth=2 --prompt="Open note > "'

local M = {}
M.open = function()
	picker.run(sink, extra)
end
return M
