;; config/keys.fnl
;; Keymaps and keybinding helpers.

(local keymap (require :utils.keymap))
(local schedule (require :utils.schedule))

(local mappings
  [;; general
   ["n" "<Esc>" "<cmd>nohlsearch<CR>"]
   ["n" "<leader>q" vim.diagnostic.setloclist
    {:desc "Open diagnostic [Q]uickfix list"}]

   ;; move lines
   ["n" "<A-J>" ":m .+1<CR>=="]
   ["n" "<A-K>" ":m .-2<CR>=="]
   ["v" "<A-J>" ":m '>+1<CR>gv=gv"]
   ["v" "<A-K>" ":m '<-2<CR>gv=gv"]

   ;; indent selection
   ["v" "<Tab>" ">>"]
   ["v" "<S-Tab>" "<<"]

   ;; fold toggles
   ["n" "<Tab>" "za"
    {:noremap true :silent true :desc "Toggle fold"}]
   ["n" "<S-Tab>" "zA"
    {:noremap true :silent true :desc "Toggle fold (recursive)"}]])

(keymap.apply mappings)

(schedule.group "keymaps"
  [{:events "FileType"
    :opts {:pattern ["markdown" "markdown.mdx"]}
    :callback
    (fn [args]
      (keymap.apply
        [["n" "<leader>o"
          (fn []
            ((. (require :utils.references) :open_reference) args.buf))
          {:buffer true
           :silent true
           :desc "Open front-matter reference"}]]))}])
