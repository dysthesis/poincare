(import-macros {: poincare!
                : poincare-init-modules!
                : poincare-compile-modules!} :macros)
(poincare! :theme lackluster)

;; expand `(include ...)` for each declared module
(poincare-init-modules!)

;; optionally try to `require` any module-local `.../config.fnl` files
(poincare-compile-modules!)
