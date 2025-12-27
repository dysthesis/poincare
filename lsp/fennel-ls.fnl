;; lsp/fennel-ls.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:cmd ["fennel-ls"]
   :filetypes ["fennel"]
   :root_dir (lsp.root-from ["flsproject.fnl"] ".git")
   :settings {}
   :capabilities {:offsetEncoding ["utf-8" "utf-16"]}})
