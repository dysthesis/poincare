(require-macros :plugins.helpers)

(local surround-opts
  {:mappings {:add "S"
              :delete "ds"
              :replace "cs"}})

(use "mini.surround"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.surround) :setup) surround-opts)))
