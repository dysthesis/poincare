(require-macros :plugins.helpers)

(local km (require :utils.keymap))
(local oil-open (km.lazy-call :oil :open))

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
