(require-macros :plugins.helpers)

(fn harpoon-list []
  (: (require :harpoon) :list))

(fn harpoon-add []
  (let [list (harpoon-list)]
    (: list :add)))

(fn harpoon-select [idx]
  (let [list (harpoon-list)]
    (: list :select idx)))

(fn harpoon-menu []
  (let [harpoon (require :harpoon)
        list (harpoon-list)]
    (: (. harpoon :ui) :toggle_quick_menu list)))

(fn mark-key [idx]
  (keymap (.. "<leader>" idx)
          (fn [] (harpoon-select idx))
          (.. "Harpoon to file [" idx "]")))

(fn generate-keys [count]
  (local keys
    [(keymap "<leader>H" harpoon-add "[H]arpoon File")
     (keymap "<leader>hl" harpoon-menu "[H]arpoon [L]ist (Quick)")])
  (for [idx 1 count]
    (table.insert keys (mark-key idx)))
  keys)

(use "harpoon2"
  :keys (generate-keys 9)
  :after
  (fn []
    (: (require :harpoon) :setup)))
