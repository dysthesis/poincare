(require-macros :lib.vim)
(require-macros :plugins.helpers)
(use "rustowl"
     :lazy false
     :after (fn []
              (local rustowl (require :rustowl))
              (rustowl.setup {:client 
                              {:on_attach (fn [_ buf]
                                            (map! [n :buffer] "<leader>o"
                                                  (fn []
                                                    (rustowl.toggle buf))
                                                  "Toggle Rust[O]wl"))}})))
