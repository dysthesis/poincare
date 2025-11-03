(import-macros {: colorscheme : plugin!} :macros)

(plugin! :lackluster.nvim :colorscheme :lackluster-night :after
         (lambda []
           ((. (require :lackluster) :setup) {:tweak_background {:menu :none
                                                                 :normal :none
                                                                 :popup :none
                                                                 :telescope :none}})))
(colorscheme "lackluster-night")
