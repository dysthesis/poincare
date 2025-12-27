(local helpers (require :plugins.helpers))
(local schedule (require :lib.schedule))
(local M {})

;; Hardcoded spec module lists to avoid runtimepath scans.
(local early-modules
  ["plugins.specs.nvim-treesitter"
   "plugins.specs.nvim-treesitter-textobjects"])

(local late-modules
  ["plugins.specs.lackluster"
   "plugins.specs.mini-extra"
   "plugins.specs.mini-icons"
   "plugins.specs.mini-pick"
   "plugins.specs.smart-splits"
   "plugins.specs.vim-tmux-navigator"])

(fn M.setup-modules [modules]
  (when (and modules (> (# modules) 0))
    (helpers.setup modules)))

;; Register minimal specs early so BufReadPost triggers are captured.
(M.setup-modules early-modules)

;; Defer the bulk of plugin spec registration until after startup.
(schedule.on "VimEnter"
  {:once true
   :desc "Register deferred plugin specs"}
  (fn [] (M.setup-modules late-modules)))

M
