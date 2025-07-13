local picker = require("utils.picker.core")
local M = {}

local RG_CMD = "rg --vimgrep --smart-case --color=always -- {q} || true"

local FZF_EXTRA = table.concat({
	"--disabled", -- start with an empty list
	"--phony", -- rely on ripgrep, no secondary filter
	"--delimiter ':'", -- so {1} = file, {2} = line, ...
	("--bind 'change:reload:%s,first'"):format(RG_CMD),
}, " ")

local function safe_open(cmd, file, row, col)
	vim.cmd(("%s +%d %s"):format(cmd, row, vim.fn.fnameescape(file)))

	vim.schedule(function()
		local max_row = vim.api.nvim_buf_line_count(0)
		row = math.min(math.max(row, 1), max_row)

		local text = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
		local maxcol = #text
		col = math.min(math.max(col, 1), maxcol)

		pcall(vim.api.nvim_win_set_cursor, 0, { row, col - 1 })
	end)
end

M.open = function()
	picker.run({
		producer = "printf ''",
		preview = "bat --style=numbers --color=always --highlight-line {2} {1}",
		extra = FZF_EXTRA,
		parse = function(lines)
			local out = {}
			for _, l in ipairs(lines) do
				local f, ln, col = l:match("^([^:]+):([^:]+):([^:]+):")
				if f then
					out[#out + 1] = { f, tonumber(ln), tonumber(col) }
				end
			end
			return out
		end,
		sink = function(matches, key)
			local map = { ["ctrl-v"] = "vsplit", ["ctrl-s"] = "split" }
			local open = map[key] or "edit"
			for _, m in ipairs(matches) do
				safe_open(open, m[1], m[2], m[3])
			end
		end,
	})
end

return M
