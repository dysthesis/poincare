local M = {}
local literal = require("ui.statusline.text")

M.hl_groups = {
  VcIcon = {
    fg = { group = "Conceal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Vc = {
    fg = { group = "Conceal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  VcDirty = {
    fg = { group = "DiagnosticInfo", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

local state = {}
local roots = {}

local function redraw()
  vim.schedule(vim.cmd.redrawstatus)
end

local backends = {
  jj = {
    marker = ".jj",

    command = function(root)
      return {
        "jj",
        "--repository",
        root,
        "--no-pager",
        "log",
        "--no-graph",
        "-r",
        "@",
        "-T",
        table.concat({
          "try(bookmarks.first().name(), change_id.shortest(8))",
          ' ++ "\\t" ++ ',
          'if(empty, "clean", "dirty")',
          ' ++ "\\n"',
        }),
      }
    end,

    parse = function(output)
      local label, status = output:match("^([^\t]+)\t([^\n]+)")

      if not label then
        return nil
      end

      return {
        label = label,
        dirty = status == "dirty",
      }
    end,
  },

  git = {
    marker = ".git",

    command = function(root)
      return {
        "git",
        "-C",
        root,
        "status",
        "--porcelain=v2",
        "--branch",
      }
    end,

    parse = function(output)
      local branch
      local oid
      local dirty = false

      for line in output:gmatch("[^\n]+") do
        if vim.startswith(line, "# branch.head ") then
          branch = line:sub(#"# branch.head " + 1)
        elseif vim.startswith(line, "# branch.oid ") then
          oid = line:sub(#"# branch.oid " + 1)
        elseif not vim.startswith(line, "#") then
          dirty = true
        end
      end

      if branch == "(detached)" then
        branch = oid and oid ~= "(initial)" and oid:sub(1, 7) or "HEAD"
      end

      if not branch then
        return nil
      end

      return {
        label = branch,
        dirty = dirty,
      }
    end,
  },
}

local backend_order = {
  "jj",
  "git",
}

local function detect(buf)
  local cached = roots[buf]

  if cached ~= nil then
    return cached or nil
  end

  for _, name in ipairs(backend_order) do
    local backend = backends[name]
    local root = vim.fs.root(buf, backend.marker)

    if root then
      local result = {
        kind = name,
        root = root,
      }

      roots[buf] = result
      return result
    end
  end

  roots[buf] = false
  return nil
end

local function refresh_repo(repo, invalidate)
  local key = repo.kind .. ":" .. repo.root
  local cached = state[key]

  if cached and cached.pending then
    if invalidate then
      cached.refresh_requested = true
    end
    return
  end

  cached = cached or {}
  state[key] = cached
  cached.pending = true
  cached.refresh_requested = false

  local backend = backends[repo.kind]

  vim.system(backend.command(repo.root), { text = true }, function(result)
    vim.schedule(function()
      local current = state[key]

      if current ~= cached then
        return
      end

      current.pending = false
      if current.refresh_requested then
        refresh_repo(repo)
        return
      end

      if result.code ~= 0 then
        current.label = nil
        current.dirty = nil
        redraw()
        return
      end

      local parsed = backend.parse(result.stdout or "")
      if not parsed then
        current.label = nil
        current.dirty = nil
        redraw()
        return
      end

      current.label = parsed.label
      current.dirty = parsed.dirty

      redraw()
    end)
  end)
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  roots[buf] = nil

  local repo = detect(buf)

  if repo then
    refresh_repo(repo, true)
  end
end

function M.component()
  local buf = vim.api.nvim_get_current_buf()
  local repo = detect(buf)

  if not repo then
    return ""
  end

  local key = repo.kind .. ":" .. repo.root
  local current = state[key]

  if not current then
    refresh_repo(repo)
    return ""
  end

  if not current.label then
    return ""
  end

  local result = {
    "%#StatusLineVcIcon#",
    " ",
    "%#StatusLineVc#",
    " ",
    literal(current.label),
  }

  if current.dirty then
    result[#result + 1] = "%#StatusLineVcDirty#"
    result[#result + 1] = " ±"
  end

  return table.concat(result)
end

local group = vim.api.nvim_create_augroup("statusline_vc", {
  clear = true,
})

vim.api.nvim_create_autocmd({
  "BufEnter",
  "BufWritePost",
  "FocusGained",
  "BufFilePost",
  "DirChanged",
}, {
  group = group,
  callback = function(event)
    M.refresh(event.buf)
  end,
})

return M
