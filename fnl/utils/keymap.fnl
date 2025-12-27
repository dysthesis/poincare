(local M {})

(fn M.apply [maps ?defaults]
  (each [_ spec (ipairs maps)]
    (let [[mode lhs rhs opts] spec
          merged (vim.tbl_extend "force" (or ?defaults {}) (or opts {}))]
      (vim.keymap.set mode lhs rhs merged))))

(fn M.lazy-call [mod path]
  (let [path (if (= (type path) :table) path (if path [path] []))]
    (fn [...]
      (var f (require mod))
      (each [_ p (ipairs path)]
        (set f (. f p)))
      (f ...))))

M
