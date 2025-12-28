(require-macros :plugins.helpers)

(local lazy-call (. (require :utils.keymap) :lazy-call))

(local oil-open (lazy-call :oil :open))

(use "oil.nvim"
     :cmd "Oil"
     :event ["VimEnter */*,.*" "BufNew */*,.*"]
     :keys [(keymap "<leader>." oil-open "Open Oil")]
     :after
     (fn []
       ((. (require :oil) :setup)
        {:skip_confirm_for_simple_edits true
         :columns ["icon"
                   "permissions"
                   "size"
                   "mtime"]})))
