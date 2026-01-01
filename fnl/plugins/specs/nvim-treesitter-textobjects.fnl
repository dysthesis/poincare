(require-macros :plugins.helpers)

(local km (require :utils.keymap))

(use "nvim-treesitter-textobjects"
  :lazy false

  :before
  (fn []
    (when (= nil vim.g.no_plugin_maps)
      (set vim.g.no_plugin_maps true)))

  :after
  (fn []
    (local group "textobjects")

    ((. (require :nvim-treesitter-textobjects) :setup)
     {:select
      {:lookahead true
       :selection_modes
       {"@block.outer" "<c-v>"
        "@frame.outer" "<c-v>"
        "@statement.outer" "V"
        "@assignment.outer" "V"
        "@comment.outer" "V"
        "@comment.inner" "v"
        "@conditional.outer" "V"
        "@conditional.inner" "v"}
       :include_surrounding_whitespace false}
      :move {:set_jumps true}})

    (local select (require :nvim-treesitter-textobjects.select))
    (local move   (require :nvim-treesitter-textobjects.move))
    (local swap   (require :nvim-treesitter-textobjects.swap))
    (local repeat (require :nvim-treesitter-textobjects.repeatable_move))

    (fn sel [query]
      (fn [] ((. select :select_textobject) query group)))

    (fn goto-next-start [query]
      (fn [] ((. move :goto_next_start) query group)))

    (fn goto-next-end [query]
      (fn [] ((. move :goto_next_end) query group)))

    (fn goto-prev-start [query]
      (fn [] ((. move :goto_previous_start) query group)))

    (fn goto-prev-end [query]
      (fn [] ((. move :goto_previous_end) query group)))

    (fn goto-next [query]
      (fn [] ((. move :goto_next) query group)))

    (fn goto-prev [query]
      (fn [] ((. move :goto_previous) query group)))

    (fn swap-next [query]
      (fn [] ((. swap :swap_next) query)))

    (fn swap-prev [query]
      (fn [] ((. swap :swap_previous) query)))

    (local maps [])

    (fn add! [mode lhs rhs desc ?opts]
      (table.insert maps 
                    [mode lhs rhs 
                          (vim.tbl_extend "force" {:desc desc} (or ?opts {}))]))

    (let [modes ["x" "o"]]
      (add! modes "af" (sel "@function.outer")      "Select function outer")
      (add! modes "if" (sel "@function.inner")      "Select function inner")

      (add! modes "ac" (sel "@class.outer")         "Select class outer")
      (add! modes "ic" (sel "@class.inner")         "Select class inner")

      (add! modes "aC" (sel "@call.outer")          "Select call outer")
      (add! modes "iC" (sel "@call.inner")          "Select call inner")

      (add! modes "a#" (sel "@comment.outer")       "Select comment outer")
      (add! modes "i#" (sel "@comment.inner")       "Select comment inner")

      (add! modes "ai" (sel "@conditional.outer")   "Select conditional outer")
      (add! modes "ii" (sel "@conditional.inner")   "Select conditional inner")

      (add! modes "al" (sel "@loop.outer")          "Select loop outer")
      (add! modes "il" (sel "@loop.inner")          "Select loop inner")

      (add! modes "aP" (sel "@parameter.outer")     "Select parameter outer")
      (add! modes "iP" (sel "@parameter.inner")     "Select parameter inner")

      ;; Assignment family
      (add! modes "aa" (sel "@assignment.outer")    "Select assignment outer")
      (add! modes "ia" (sel "@assignment.inner")    "Select assignment inner")
      (add! modes "aL" (sel "@assignment.lhs")      "Select assignment LHS")
      (add! modes "iL" (sel "@assignment.lhs")      "Select assignment LHS inner")
      (add! modes "aR" (sel "@assignment.rhs")      "Select assignment RHS")
      (add! modes "iR" (sel "@assignment.rhs")      "Select assignment RHS inner")

      ;; Attributes / fields
      (add! modes "aA" (sel "@attribute.outer")     "Select attribute outer")
      (add! modes "iA" (sel "@attribute.inner")     "Select attribute inner")

      ;; Blocks / frames
      (add! modes "ab" (sel "@block.outer")         "Select block outer")
      (add! modes "ib" (sel "@block.inner")         "Select block inner")
      (add! modes "aF" (sel "@frame.outer")         "Select frame outer")
      (add! modes "iF" (sel "@frame.inner")         "Select frame inner")

      ;; Literals and statements
      (add! modes "an" (sel "@number.outer")        "Select number outer")
      (add! modes "in" (sel "@number.inner")        "Select number inner")
      (add! modes "aX" (sel "@regex.outer")         "Select regex outer")
      (add! modes "iX" (sel "@regex.inner")         "Select regex inner")
      (add! modes "ar" (sel "@return.outer")        "Select return outer")
      (add! modes "ir" (sel "@return.inner")        "Select return inner")
      (add! modes "as" (sel "@statement.outer")     "Select statement outer")

      ;; Names
      (add! modes "ns" (sel "@scopename.inner")     "Select scope name"))

    ;; Move (normal + operator-pending + visual)
    (let [m ["n" "x" "o"]]
      ;; Conventional function motions
      (add! m "]m" (goto-next-start "@function.outer")   "Next function start")
      (add! m "]M" (goto-next-end   "@function.outer")   "Next function end")
      (add! m "[m" (goto-prev-start "@function.outer")   "Previous function start")
      (add! m "[M" (goto-prev-end   "@function.outer")   "Previous function end")

      ;; Parameters
      (add! m "]P" (goto-next-start "@parameter.outer")  "Next parameter start")
      (add! m "]p" (goto-next-end   "@parameter.outer")  "Next parameter end")
      (add! m "[P" (goto-prev-start "@parameter.outer")  "Previous parameter start")
      (add! m "[p" (goto-prev-end   "@parameter.outer")  "Previous parameter end")

      ;; “Closest end or start” conditional navigation
      (add! m "]d" (goto-next "@conditional.outer")      "Next conditional (closest edge)")
      (add! m "[d" (goto-prev "@conditional.outer")      "Previous conditional (closest edge)"))

    ;; Swap (normal)
    (add! "n" "<leader>a" (swap-next "@parameter.inner")  "Swap with next parameter")
    (add! "n" "<leader>A" (swap-prev "@parameter.inner")  "Swap with previous parameter")

    ;; Repeatable motions (normal + operator-pending + visual)
    (add! ["n" "x" "o"] 
          ";" 
          (. repeat :repeat_last_move_next)
          "Repeat last TS move forwards")
    (add! ["n" "x" "o"]
          "," 
          (. repeat :repeat_last_move_previous)
          "Repeat last TS move backwards")

    (add! ["n" "x" "o"]
          "f" 
          (. repeat :builtin_f_expr) 
          "f (repeatable)" 
          {:expr true})
    (add! ["n" "x" "o"] 
          "F" 
          (. repeat :builtin_F_expr)
          "F (repeatable)"
          {:expr true})

    (add! ["n" "x" "o"]
          "t" 
          (. repeat :builtin_t_expr) 
          "t (repeatable)" 
          {:expr true})
    (add! ["n" "x" "o"] 
          "T" 
          (. repeat :builtin_T_expr) 
          "T (repeatable)" 
          {:expr true})

    (km.apply maps {:silent true})))
