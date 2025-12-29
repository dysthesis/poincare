(require-macros :plugins.helpers)
(use "lean.nvim"
     :event ["BufReadPre *.lean" "BufNewFile *.lean"]
     :after (fn []
              ((. (require :lean) :setup) {:mappings true})))
