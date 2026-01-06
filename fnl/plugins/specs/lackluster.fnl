(require-macros :plugins.helpers)

(use "lackluster.nvim"
  :priority 100
  :event "VimEnter"
  :after
  (fn []
    (local lackluster (require :lackluster))
    (lackluster.setup {:tweak_background {:normal    :none
                                          :telescope :none
                                          :menu      :none
                                          :popup     :none}})

    (lackluster.load {:theme "minimal"})
    (vim.api.nvim_set_hl 0
                         :Folded
                         {:bg "#191919"})))
