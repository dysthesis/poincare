(local mini-icons (require :mini.icons))
(mini-icons.setup)

(local lackluster (require :lackluster))
(local c (. lackluster :color))
(local set-hl vim.api.nvim_set_hl)

(local highlights
  [["MiniIconsAzure"  (. c :lack)]
   ["MiniIconsBlue"   (. c :hint)]
   ["MiniIconsGreen"  (. c :special)]
   ["MiniIconsGrey"   (. c :gray4)]
   ["MiniIconsPurple" "#cba6f7"]
   ["MiniIconsOrange" (. c :warn)]
   ["MiniIconsRed"    (. c :warn)]
   ["MiniIconsYellow" "#f9e2af"]])

(each [_ pair (ipairs highlights)]
  (set-hl 0 (. pair 1) {:fg (. pair 2)}))
