(require-macros :plugins.helpers)
(use "mini.clue"
     :event "DeferredUIEnter"
     :after
     (fn []
       (local miniclue (require :mini.clue))
       (local gen-clues (. miniclue :gen_clues))
       (local triggers
         [;; Leader triggers
          {:mode "n"
           :keys "<leader>"}
          {:mode "x"
           :keys "<leader>"}

          ;; Built-in completion
          {:mode "i"
           :keys "<C-x>"}

          ;; `g` key
          {:mode "n"
           :keys "g"}
          {:mode "x"
           :keys "g"}

          ;; Marks
          {:mode "n"
           :keys "'"}
          {:mode "n"
           :keys "`"}
          {:mode "x"
           :keys "'"}
          {:mode "x"
           :keys "`"}

          ;; Registers
          {:mode "n"
           :keys "\""}
          {:mode "x"
           :keys "\""}
          {:mode "i"
           :keys "<C-r>"}
          {:mode "c"
           :keys "<C-r>"}

          ;; Window commands
          {:mode "n"
           :keys "<C-w>"}

          ;; `z` key
          {:mode "n"
           :keys "z"}
          {:mode "x"
           :keys "z"}])
       (local clues
         [;; Enhance this by adding descriptions for <leader> mapping groups
          ((. gen-clues :builtin_completion))
          ((. gen-clues :g))
          ((. gen-clues :marks))
          ((. gen-clues :registers))
          ((. gen-clues :windows))
          ((. gen-clues :z))])

       (miniclue.setup {:window {:delay 0}
                        :triggers triggers
                        :clues clues})))
