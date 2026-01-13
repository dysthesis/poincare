(require-macros :plugins.helpers)
(require-macros :lib.vim)

(use "minimal.nvim"
     :priority 100
     :event "VimEnter"
     :after
     (fn []
       (g! minimal_transparent true)
       (g! minimal_bold_defs true)
       (g! minimal_bold_introductions true)
       (set! background "dark")
       (vim.cmd.colorscheme "minimal")))
