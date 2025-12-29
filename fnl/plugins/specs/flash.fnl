(require-macros :plugins.helpers)

(local lazy-call (. (require :utils.keymap) :lazy-call))

(local flash-jump (lazy-call :flash [:jump]))
(local flash-treesitter (lazy-call :flash [:treesitter]))
(local flash-remote (lazy-call :flash [:remote]))
(local flash-treesitter-search (lazy-call :flash [:treesitter_search]))
(local flash-toggle (lazy-call :flash [:toggle]))

(fn with-mode [lhs rhs modes desc]
  (local entry (keymap lhs rhs desc))
  (set entry.mode modes)
  entry)

(local flash-opts {})

(use "flash.nvim"
     :event "DeferredUIEnter"
     :keys
     [(with-mode "s" flash-jump ["n" "x" "o"] "Flash")
      (with-mode "S" flash-treesitter ["n" "x" "o"] "Flash Treesitter")
      (with-mode "r" flash-remote "o" "Remote Flash")
      (with-mode "R" flash-treesitter-search ["o" "x"] "Treesitter Search")
      (with-mode "<c-s>" flash-toggle "c" "Toggle Flash Search")]
     :after
     (fn []
       ((. (require :flash) :setup) flash-opts)))
