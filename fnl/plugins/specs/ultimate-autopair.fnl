(require-macros :plugins.helpers)

(use "ultimate-autopair.nvim"
  :event ["InsertEnter" "CmdlineEnter"]
  :after
  (fn []
    ((. (require :ultimate-autopair) :setup) {})))
