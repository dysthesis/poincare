(require-macros :plugins.helpers)
(use "mini.ai"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.ai) :setup))))
