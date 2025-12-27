;; config/keys.fnl
;; Keymaps and keybinding helpers.

(require-macros :lib.vim)

(local api vim.api)

(g! :mapleader " ")
(g! :maplocalleader " ")

(fn kmap [mode lhs rhs ?opts]
  (vim.keymap.set mode lhs rhs (or ?opts {})))

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

(each [_ [mode lhs rhs opts] (ipairs mappings)]
  (kmap mode lhs rhs opts))

(api.nvim_create_autocmd "FileType"
  {:pattern ["markdown" "markdown.mdx"]
   :callback
   (fn [args]
     (kmap "n" "<leader>o"
           (fn []
             ((. (require :utils.references) :open_reference) args.buf))
           {:buffer true
            :silent true
            :desc "Open front-matter reference"}))})
