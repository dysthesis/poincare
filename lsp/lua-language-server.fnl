;; lsp/lua-language-server.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:cmd ["lua-language-server"]
   :filetypes ["lua"]
   :root_markers [".luarc.json" ".luarc.jsonc"]
   :settings
   {:Lua
    {:workspace
     {:library (vim.api.nvim_get_runtime_file "" true)}}}})
