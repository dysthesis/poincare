(require-macros :plugins.helpers)

(local km (require :utils.keymap))

(local pick-files (km.lazy-call :mini.pick [:builtin :files]))
(local pick-grep (km.lazy-call :mini.pick [:builtin :grep_live]))
(local pick-lines (km.lazy-call :mini.pick [:registry :buffer_lines_current]))
(local pick-diagnostics (km.lazy-call :mini.extra [:pickers :diagnostic]))
(local pick-explorer (km.lazy-call :mini.extra [:pickers :explorer]))
(local pick-git-commits (km.lazy-call :mini.extra [:pickers :git_commits]))
(local pick-git-branches (km.lazy-call :mini.extra [:pickers :git_branches]))
(local pick-treesitter (km.lazy-call :mini.extra [:pickers :treesitter]))
(local pick-lsp (km.lazy-call :mini.extra [:pickers :lsp]))

(use "mini.pick"
   :cmd "Pick"
   :keys
   [(keymap "<leader>f" pick-files "Find [F]iles")
    (keymap "<leader>/" pick-grep "Find [G]rep")
    (keymap "<leader>l" pick-lines "Find buffer [L]ines")
    (keymap "<leader>d" pick-diagnostics "Find [D]iagnostics")
    (keymap "<leader>e" pick-explorer "Find [E]xplorer")
    (keymap "<leader>g" pick-git-commits "Find [G]it commits")
    (keymap "<leader>G" pick-git-branches "Find [G]it branches")
    (keymap "<leader>s"
      (fn [] (pick-lsp {:scope "document_symbol"}))
      "Find [S]ymbols")
    (keymap "<leader>S"
      (fn [] (pick-lsp {:scope "workspace_symbol"}))
      "Find Workspace [S]ymbols")
    (keymap "<leader>r"
      (fn [] (pick-lsp {:scope "references"}))
      "Find [R]eferences")
    (keymap "<leader>i"
      (fn [] (pick-lsp {:scope "implementation"}))
      "Find [I]mplementation")
    (keymap "<leader>T" pick-treesitter "Find [T]reesitter nodes")]

   :after
   (fn []
     (local api vim.api)
     (local MiniPick (require :mini.pick))
     (local MiniExtra (require :mini.extra))

     (local ns-digit-prefix (api.nvim_create_namespace "cur-buf-pick-show"))

     (fn show-cur-buf-lines [buf-id items query opts]
       "Treesitter-highlighted picker for the current buffer's line"
       (when (and items (> (# items) 0))
         ;; Show as usual.
         ((. MiniPick :default_show) buf-id items query opts)

         ;; Move prefix line numbers into inline extmarks.
         (local lines (api.nvim_buf_get_lines buf-id 0 -1 false))
         (local digit-prefixes {})

         (each [i l (ipairs lines)]
           (local (_ prefix-end prefix) (l:find "^(%s*%d+│)"))
           (when prefix-end
             (tset digit-prefixes i prefix)
             (tset lines i (l:sub (+ prefix-end 1)))))

         (api.nvim_buf_set_lines buf-id 0 -1 false lines)

         ;; Clear previous extmarks, otherwise they accumulate as the
         ;; picker refreshes.
         (api.nvim_buf_clear_namespace buf-id ns-digit-prefix 0 -1)

         (each [i pref (pairs digit-prefixes)]
           (local em-opts
             {:virt_text [[pref "MiniPickNormal"]]
              :virt_text_pos "inline"})
           (api.nvim_buf_set_extmark buf-id ns-digit-prefix (- i 1) 0 em-opts))

         ;; Set highlighting based on the current filetype
         (local first-item (. items 1))
         (local ft (. vim.bo (. first-item :bufnr) :filetype))

         (local (has-lang lang) (pcall vim.treesitter.language.get_lang ft))
         (local lang* (if (and has-lang lang) lang ft))

         (local (has-ts _) (pcall vim.treesitter.start buf-id lang*))
         (when (and (not has-ts) ft)
           (tset (. vim.bo buf-id) :syntax ft))))

     ;; Override MiniPick registry entry, using the custom show function
     (tset (. MiniPick :registry) :buffer_lines_current
       (fn []
         (local local-opts {:scope "current"})
         ((. MiniExtra :pickers :buf_lines) local-opts
           {:source {:show show-cur-buf-lines}})))

     ;; Regular MiniPick setup.
     ((. MiniPick :setup)
      {:options {:use_cache true}
       :mappings {:move_down "<C-j>"
                  :move_up "<C-k>"}
       :window {:prompt_prefix "   "
                :config
                (fn []
                  (local height (math.floor (* 0.618 vim.o.lines)))
                  (local width  (math.floor (* 0.618 vim.o.columns)))
                  {:anchor "NW"
                   :border "rounded"
                   :height height
                   :width width
                   :row (math.floor (* 0.5 (- vim.o.lines height)))
                   :col (math.floor (* 0.5 (- vim.o.columns width)))})}})

     ;; Use MiniPick as vim.ui.select implementation.
     (set vim.ui.select (. MiniPick :ui_select))))
