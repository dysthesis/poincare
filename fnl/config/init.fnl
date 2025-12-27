(local api vim.api)

(require :config.behaviour)
(require :config.keys)
(require :config.statusline)
(require :config.ui)

(api.nvim_create_autocmd ["BufReadPre" "BufNewFile"]
  {:desc "Load LSP config on first file read"
   :once true
   :callback (fn [] (require :config.lsp))})
