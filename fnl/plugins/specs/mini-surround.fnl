(require-macros :plugins.helpers)

(local surround-opts
  ;; Use `g`-prefixed mappings to avoid `y` ambiguity and keep Flash on `s/S`.
  {:mappings {:add "ga"
              :delete "gd"
              :replace "gc"
              :find "gf"
              :find_left "gF"}})

(use "mini.surround"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.surround) :setup) surround-opts)))
