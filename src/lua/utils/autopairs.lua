local autopairs = {
  ['('] = ')',
  ['['] = ']',
  ['{'] = '}',
  ['"'] = '"',
  ["'"] = "'",
  ['`'] = '`',
}

_G.smart_autopair = function(open_char)
  -- Get the character that the keypress would overwrite.
  local line = vim.api.nvim_get_current_line()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local char_after_cursor = string.sub(line, col + 1, col + 1)

  -- The condition: if the next character is whitespace, a closing pair, or nothing (end of line)
  if char_after_cursor == '' or char_after_cursor:match('[%s%)%}%]]') then
    -- Return the string to be inserted: '()' + move cursor left
    return open_char .. autopairs[open_char] .. '<Left>'
  else
    -- Otherwise, just return the character typed
    return open_char
  end
end

-- Loop through the pairs and create the expression mappings
for open_char, _ in pairs(autopairs) do
  local escaped_char = string.gsub(open_char, "'", "''")

  -- Now we build the command using the escaped character.
  local command = "v:lua._G.smart_autopair('" .. escaped_char .. "')"

  vim.keymap.set('i', open_char, command, { expr = true, noremap = true, silent = true })
end
