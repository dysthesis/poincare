(require-macros :plugins.helpers)
(use "gitsigns.nvim"
     :event "BufReadPost"
     :after 
     (fn []
       ((. (require :gitsigns) :setup) {:signs {:add {:text "│"}
                                                :change {:text "│"}
                                                :delete {:text "󰍵"}
                                                :topdelete {:text "‾"}
                                                :changedelete {:text "~"}
                                                :untracked {:text "┆"}}
                                        :current_line_blame true
                                        :on_attach
                                        (fn [bufnr]
                                          (local gs package.loaded.gitsigns)
                                          (local map vim.keymap.set)
                                          (fn opts [desc] {:buffer bufnr
                                                           :desc desc})
                                          (map "n" 
                                               "<leader>hr" 
                                               gs.reset_hunk 
                                               (opts "Reset Hunk"))
                                          (map "n"
                                               "<leader>hp"
                                               gs.preview_hunk
                                               (opts "Preview Hunk"))
                                          (map "n"
                                               "<leader>b"
                                               gs.blame_line
                                               (opts "Blame Line")))})))
