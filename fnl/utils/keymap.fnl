(local M {})

(fn M.apply [maps ?defaults]
  (each [_ spec (ipairs maps)]
    (let [[mode lhs rhs opts] spec
          merged (vim.tbl_extend "force" (or ?defaults {}) (or opts {}))]
      (vim.keymap.set mode lhs rhs merged))))

(fn M.lazy-call [mod ?path]
  (local path-list
    (if (= (type ?path) :table)
        ?path
        (if ?path [?path] [])))
  (fn [...]
    (var target (require mod))
    (each [_ part (ipairs path-list)]
      (set target (. target part)))
    (target ...)))

M
