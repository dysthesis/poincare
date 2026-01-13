(local helpers (require :plugins.helpers))
(local schedule (require :utils.schedule))
(local M {})

;; Hardcoded spec module lists to avoid runtimepath scans.
;; Register the colourscheme early to reduce visible switching.
(local early-modules
  ["plugins.specs.minimal"
   "plugins.specs.nvim-treesitter"
   "plugins.specs.nvim-treesitter-textobjects"
   "plugins.specs.smart-splits"])

;; All other specs are registered after VimEnter to minimise startup overhead.
(local late-modules
  ["plugins.specs.friendly-snippets"
   "plugins.specs.luasnip"
   "plugins.specs.blink-cmp"
   "plugins.specs.oil"
   "plugins.specs.conform"
   "plugins.specs.inc-rename"
   "plugins.specs.harpoon"
   "plugins.specs.rustaceanvim"
   "plugins.specs.mini-extra"
   "plugins.specs.mini-icons"
   "plugins.specs.mini-clue"
   "plugins.specs.mini-pick"
   "plugins.specs.mini-ai"
   "plugins.specs.mini-surround"
   "plugins.specs.mini-indentscope"
   "plugins.specs.ultimate-autopair"
   "plugins.specs.zen-mode"
   "plugins.specs.twilight"
   "plugins.specs.lean"
   "plugins.specs.gitsigns"
   "plugins.specs.nvim-lint"
   "plugins.specs.flash"
   "plugins.specs.vim-tmux-navigator"])

(fn M.setup-modules [modules]
  (when (and modules (> (# modules) 0))
    (helpers.setup modules)))

;; Register minimal specs early so their events can trigger.
(M.setup-modules early-modules)

;; Defer the bulk of plugin spec registration until after startup.
(schedule.on "VimEnter"
  {:once true
   :desc "Register deferred plugin specs"}
  (fn [] (M.setup-modules late-modules)))

M
