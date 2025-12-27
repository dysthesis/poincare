(require-macros :plugins.helpers)

(use "nvim-treesitter"
  :after
  (fn []
    (set vim.g.skip_ts_context_comment_string_module true)

    ((. (require :lz.n) :trigger_load) "nvim-treesitter-textobjects")

    ((. (require :nvim-treesitter.configs) :setup)
     {:highlight {:enable true
                  :disable ["latex"]}
      :incremental_selection
      {:enable true
       :keymaps {:init_selection "<cr>"
                 :node_incremental "<cr>"
                 :scope_incremental false
                 :node_decremental "<s-tab>"}}
      :textobjects
      {:select
       {:enable true
        ;; Automatically jump forward to textobject, similar to targets.vim
        :lookahead true
        :keymaps {"af" "@function.outer"
                  "if" "@function.inner"
                  "ac" "@class.outer"
                  "ic" "@class.inner"
                  "aC" "@call.outer"
                  "iC" "@call.inner"
                  "a#" "@comment.outer"
                  "i#" "@comment.inner"
                  "ai" "@conditional.outer"
                  "ii" "@conditional.outer"
                  "al" "@loop.outer"
                  "il" "@loop.inner"
                  "aP" "@parameter.outer"
                  "iP" "@parameter.inner"

                  ;; Assignment
                  "aa" "@assignment.outer"
                  "ia" "@assignment.inner"
                  ;; LHS / RHS (optional)
                  "aL" "@assignment.lhs"
                  "iL" "@assignment.lhs"
                  "aR" "@assignment.rhs"
                  "iR" "@assignment.rhs"

                  ;; Attributes / fields
                  "aA" "@attribute.outer"
                  "iA" "@attribute.inner"

                  ;; Blocks
                  "ab" "@block.outer"
                  "ib" "@block.inner"

                  ;; Frames (language-specific grouping)
                  "aF" "@frame.outer"
                  "iF" "@frame.inner"

                  ;; Numbers
                  "an" "@number.outer"
                  "in" "@number.inner"

                  ;; Regex literals
                  "aX" "@regex.outer"
                  "iX" "@regex.inner"

                  ;; Return statements
                  "ar" "@return.outer"
                  "ir" "@return.inner"

                  ;; Statements
                  "as" "@statement.outer"

                  ;; Scope names (function / class names)
                  "ns" "@scopename.inner"}
        :selection_modes {"@block.outer" "<c-v>"
                          "@frame.outer" "<c-v>"
                          "@statement.outer" "V"
                          "@assignment.outer" "V"
                          "@comment.outer" "V"
                          "@comment.inner" "v"
                          "@conditional.inner" "v"}}
       :swap
       {:enable true
        :swap_next {"<leader>a" "@parameter.inner"}
        :swap_previous {"<leader>A" "@parameter.inner"}}
       :move
       {:enable true
        :set_jumps true
        ;; whether to set jumps in the jumplist
        :goto_next_start {"]m" "@function.outer"
                          "]P" "@parameter.outer"}
        :goto_next_end {"]m" "@function.outer"
                        "]P" "@parameter.outer"}
        :goto_previous_start {"[m" "@function.outer"
                              "[P" "@parameter.outer"}
        :goto_previous_end {"[m" "@function.outer"
                            "[P" "@parameter.outer"}}
       :nsp_interop
       {:enable true
        :peek_definition_code {"df" "@function.outer"
                               "dF" "@class.outer"}}}})

    (vim.filetype.add
      {:pattern {".*/hypr/.*%.conf" "hyprlang"}
       :extension {:sage "python"}})))
