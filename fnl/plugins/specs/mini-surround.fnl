(require-macros :plugins.helpers)

(local surround-opts
  ;; Use `ys` (à la tpope/vim-surround) to avoid clashing with Flash's `S`
  ;; Treesitter jump while keeping familiar `ds`/`cs` motions.
  {:mappings {:add "ys"
              :delete "ds"
              :replace "cs"
              :find "gs"
              :find_left "gS"}})

(use "mini.surround"
     :event "BufReadPost"
     :after
     (fn []
       ((. (require :mini.surround) :setup) surround-opts)))
