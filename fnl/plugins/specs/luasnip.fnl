(require-macros :plugins.helpers)

(use "LuaSnip"
  :event "InsertEnter"
  :after
  (fn []
    (vim.cmd.packadd "friendly-snippets")

    (local ls (require :luasnip))

    ((. (. ls :config) :setup)
     {:history true
      :updateevents "TextChanged,TextChangedI"
      :enable_autosnippets false})

    ((. (require :luasnip.loaders.from_vscode) :lazy_load))))
