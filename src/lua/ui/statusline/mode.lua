local M = {}

M.mode_settings = {
  ["n"] = "NOR",
  ["no"] = "OP-PENDING",
  ["nov"] = "OP-PENDING",
  ["noV"] = "OP-PENDING",
  ["no\22"] = "OP-PENDING",
  ["niI"] = "NOR",
  ["niR"] = "NOR",
  ["niV"] = "NOR",
  ["nt"] = "NOR",
  ["ntT"] = "NOR",
  ["v"] = "VIS",
  ["vs"] = "VIS",
  ["V"] = "V-LINE",
  ["Vs"] = "V-LINE",
  ["\22"] = "V-BLOCK",
  ["\22s"] = "V-BLOCK",
  ["s"] = "SELECT",
  ["S"] = "S-LINE",
  ["\19"] = "S-BLOCK",
  ["i"] = "INS",
  ["ic"] = "INS",
  ["ix"] = "INS",
  ["R"] = "REP",
  ["Rc"] = "REP",
  ["Rx"] = "REP",
  ["Rv"] = "V-REP",
  ["Rvc"] = "V-REP",
  ["Rvx"] = "V-REP",
  ["c"] = "CMD",
  ["cv"] = "EX",
  ["ce"] = "EX",
  ["r"] = "REP",
  ["rm"] = "MORE",
  ["r?"] = "CONF",
  ["!"] = "SH",
  ["t"] = "TER",
}

function M.component()
  local mode = M.mode_settings[vim.fn.mode()] or {}
  return "%#StatusLineMode#" .. mode
end

return M
