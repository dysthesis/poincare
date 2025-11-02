(local lackluster (require :lackluster))
(lackluster.setup {:tweak-background {:normal "none"
                                      :telescope "none"
                                      :menu "none"
                                      :popup "none"}})
(vim.cmd.colorscheme :lackuster-night)
(vim.api.nvim_set_hl 0 "Folded" {:bg "#191919"})
