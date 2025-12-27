(local schedule (require :utils.schedule))

(require :config.behaviour)
(require :config.ui)

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
