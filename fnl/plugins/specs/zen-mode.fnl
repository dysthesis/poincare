(require-macros :plugins.helpers)
(use "zen-mode.nvim"
     :keys [(keymap "<leader>z" 
                    (fn [] ((. (require :zen-mode) :toggle)))
                    "Toggle [Z]en")])
