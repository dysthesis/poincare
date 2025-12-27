(require-macros :plugins.helpers)

(use "mini.icons"
  :after
  (fn []
    (local mini-icons (require :mini.icons))
    (mini-icons.setup)

    (local lackluster (require :lackluster))
    (local colour (. lackluster :color))
    (local set-hl vim.api.nvim_set_hl)

    (local highlights
      [["MiniIconsAzure"  (. colour :lack)]
       ["MiniIconsBlue"   (. colour :hint)]
       ["MiniIconsGreen"  (. colour :special)]
       ["MiniIconsGrey"   (. colour :gray4)]
       ["MiniIconsPurple" "#cba6f7"]
       ["MiniIconsOrange" (. colour :warn)]
       ["MiniIconsRed"    (. colour :warn)]
       ["MiniIconsYellow" "#f9e2af"]])

    (each [_ pair (ipairs highlights)]
      (set-hl 0 (. pair 1) {:fg (. pair 2)}))))
