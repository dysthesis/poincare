(require-macros :plugins.helpers)

(local ui (require :utils.ui))

(use "mini.icons"
     :event "DeferredUIEnter"
     :after
     (fn []
       (local mini-icons (require :mini.icons))
       (mini-icons.setup)
       (local lackluster (require :lackluster))
       (local colour (. lackluster :color))
       (local highlights
         [["MiniIconsAzure"  {:fg (. colour :lack)}]
          ["MiniIconsBlue"   {:fg (. colour :hint)}]
          ["MiniIconsGreen"  {:fg (. colour :special)}]
          ["MiniIconsGrey"   {:fg (. colour :gray4)}]
          ["MiniIconsPurple" {:fg "#cba6f7"}]
          ["MiniIconsOrange" {:fg (. colour :warn)}]
          ["MiniIconsRed"    {:fg (. colour :warn)}]
          ["MiniIconsYellow" {:fg "#f9e2af"}]])
       (ui.apply-highlights highlights)))
