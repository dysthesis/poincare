;; This file is the entrypoint of the configuration.
(vim.cmd.colorscheme "lackluster")
(import-macros {: poincare! : poincare-init-modules! : poincare-compile-modules!} :macros)

(poincare!
  :theme
  lackluster)
