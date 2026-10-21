local function canonical(path)
  -- Resolve the existing prefix too when editing an unsaved file in a new
  -- directory. Normalize literally: '$NAME' can be part of a real filename.
  local current = path
  local suffix = {}
  while true do
    local resolved = vim.uv.fs_realpath(current)
    if resolved then
      for index = #suffix, 1, -1 do
        resolved = vim.fs.joinpath(resolved, suffix[index])
      end
      return vim.fs.normalize(resolved, { expand_env = false })
    end
    local parent = vim.fs.dirname(current)
    if parent == current then
      return vim.fs.normalize(path, { expand_env = false })
    end
    suffix[#suffix + 1] = vim.fs.basename(current)
    current = parent
  end
end

return {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
  root_dir = function(bufnr, on_dir)
    local root =
      vim.fs.root(bufnr, vim.lsp.config["lua-language-server"].root_markers)
    if not root then
      -- before_init has no buffer context. Give markerless config files their
      -- own root rather than sharing an ordinary rootless client's settings.
      local filename = vim.api.nvim_buf_get_name(bufnr)
      local directory = filename ~= "" and vim.fs.dirname(canonical(filename))
        or nil
      local config_root = canonical(vim.fn.stdpath("config"))
      local prefix = config_root:gsub("/+$", "") .. "/"
      if
        directory
        and (directory == config_root or vim.startswith(directory, prefix))
      then
        root = config_root
      end
    end
    on_dir(root)
  end,
  before_init = function(params, config)
    local workspace = config.settings.Lua.workspace
    if workspace.library ~= nil then
      return
    end

    local root = params.rootUri ~= vim.NIL
        and params.rootUri
        and canonical(vim.uri_to_fname(params.rootUri))
      or nil
    -- Client.settings already holds this table; do not replace config.settings
    -- or send a late configuration notification that reloads the workspace.
    workspace.library = root == canonical(vim.fn.stdpath("config"))
        and { vim.env.VIMRUNTIME }
      or {}
  end,
  settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",
        path = { "lua/?.lua", "lua/?/init.lua" },
      },
      workspace = {
        checkThirdParty = false,
      },
      completion = { callSnippet = "Replace" },
      telemetry = { enable = false },
      hint = {
        enable = true,
        semicolon = "Disable",
      },
      codeLens = { enable = true },
    },
  },
}
