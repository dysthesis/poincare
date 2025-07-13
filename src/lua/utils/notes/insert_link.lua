local picker = require("utils.picker.notes")

local function urlencode(str)
	return str:gsub("([^A-Za-z0-9_%-%.~])", function(c)
		return string.format("%%%02X", c:byte())
	end)
end

local M = {}
M.open = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local cur = vim.api.nvim_win_get_cursor(0)
	local row = cur[1] - 1
	local col = cur[2]

	local sink = function(lines, _)
		local sel = lines[#lines]
		if not sel then
			return
		end

		local title, path = sel:match("(.+):(.+)")
		if not (title and path) then
			vim.notify("Selection not in title:path format", vim.log.levels.WARN)
			return
		end

		local encoded = urlencode(path)

		local formatted = ("[%s](%s)"):format(title, encoded)

		vim.api.nvim_buf_set_text(
			bufnr,
			row,
			col, -- start (inclusive)
			row,
			col, -- end (exclusive)
			{ formatted }
		)

		-- move the cursor to just after the inserted text
		-- new column = old col + length of formatted
		local new_col = col + #formatted
		vim.api.nvim_win_set_cursor(0, { row + 1, new_col })
	end

	local extra = " --accept-nth '{1}:{2}' --prompt=\"Insert link to note > \""
	picker.run(sink, extra)
end

return M
