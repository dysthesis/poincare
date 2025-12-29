;; lsp/bash-language-server.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:cmd ["bash-language-server" "start"]
   :filetypes ["bash" "sh"]})
