local M = {}

local function discover(pattern, prefix)
  local result = {}

  for _, path in ipairs(vim.api.nvim_get_runtime_file(pattern, true)) do
    local name = vim.fs.basename(path):gsub("%.lua$", "")

    if result[name] == nil then
      result[name] = require(prefix .. "." .. name)
    end
  end

  return result
end

M.modules = discover("lua/lang/modules/*.lua", "lang.modules")

M.specs = discover("lua/lang/specs/*.lua", "lang.specs")

function M.setup()
  local diagnostic_text = {
    spacing = 2,
    source = "if_many",
    virt_text_pos = "eol",
  }

  vim.diagnostic.config({
    virtual_text = diagnostic_text,
  })

  local diagnostics_active = true
  vim.keymap.set("n", "<leader>D", function()
    diagnostics_active = not diagnostics_active
    if diagnostics_active then
      vim.diagnostic.show()
    else
      vim.diagnostic.hide()
    end
  end)

  for name, lang in pairs(M.specs) do
    lang.filetypes = lang.filetypes or { name }

    for field, value in pairs(lang) do
      local module = M.modules[field]

      if module ~= nil then
        module(lang, value)
      end
    end
  end
end

return M
