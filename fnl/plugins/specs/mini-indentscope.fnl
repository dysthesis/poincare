(require-macros :plugins.helpers)
(use "mini.indentscope"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.indentscope) :setup)))) 
