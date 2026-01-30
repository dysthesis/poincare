(require-macros :plugins.helpers)

(local surround-opts
  ;; Use `g`-prefixed mappings to avoid `y` ambiguity and keep Flash on `s/S`.
  {:mappings {:add "gsa"
              :delete "gsd"
              :replace "gsc"
              :find "gsf"
              :find_left "gsF"}})

(use "mini.surround"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.surround) :setup) surround-opts)))
