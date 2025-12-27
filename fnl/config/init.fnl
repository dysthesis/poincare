(local schedule (require :utils.schedule))

(require :config.behaviour)
(require :config.ui)

(schedule.require-on "User"
  ["config.keys" "config.statusline"]
  {:pattern "DeferredUIEnter"
   :desc "Load keymaps and statusline after UI enter"})

(schedule.require-on ["BufReadPre" "BufNewFile"]
  "config.lsp"
  {:desc "Load LSP config on first file read"})
