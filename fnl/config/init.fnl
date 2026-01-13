(local schedule (require :utils.schedule))

(require :config.codelldb)
(require :config.behaviour)
(require :config.ui)
(require :config.treesitter-rust-override)

(schedule.require-on "UIEnter"
  "config.statusline"
  {:desc "Load statusline on UI enter"
   :schedule false})

(schedule.require-on "User"
  "config.keys"
  {:pattern "DeferredUIEnter"
   :desc "Load keymaps after deferred UI enter"})

(schedule.require-on ["BufReadPre" "BufNewFile"]
  "config.lsp"
  {:desc "Load LSP config on first file read"})

(schedule.require-on ["BufReadPre" "BufNewFile"]
  "config.complexity"
  {:desc "Load complexity hints on first file read"})
