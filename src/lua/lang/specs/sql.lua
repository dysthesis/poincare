local function use(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  -- Dadbod decodes percent escapes and treats ? and # as URL delimiters.
  path = path:gsub("[?@$=&<>%%#%s]", function(char)
    return ("%%%02X"):format(char:byte())
  end)
  vim.b.db = "sqlite:" .. path
end

return {
  formatters = {
    {
      "sqruff",
      "--dialect",
      "sqlite",
      "fix",
      "-",
    },
  },
  linters = "sqruff",
  lsp = "sqls",
  setup = function()
    require("lz.n").load({
      "vim-dadbod",
      commands = "DB",
    })
    vim.api.nvim_create_user_command("SQLiteUse", function(opts)
      use(opts.args)
    end, {
      nargs = 1,
      complete = "file",
    })

    vim.keymap.set("n", "<leader>dq", "<cmd>%DB<cr>", {
      desc = "Run SQL query",
    })

    vim.keymap.set("x", "<leader>dq", ":DB<cr>", {
      desc = "Run SQL selection",
    })
  end,
}
