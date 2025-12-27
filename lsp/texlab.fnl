;; lsp/texlab.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:cmd ["texlab"]
   :filetypes ["tex" "plaintex" "bib"]
   :settings
   {:texlab
    {:rootDirectory nil
     :build
     {:executable "latexmk"
      :args ["-pdf" "-interaction=nonstopmode" "-synctex=1" "%f"]
      :onSave false
      :forwardSearchAfter false}
     :forwardSearch
     {:executable nil
      :args []}
     :chktex
     {:onOpenAndSave false
      :onEdit false}
     :diagnosticsDelay 300
     :latexFormatter "latexindent"
     :latexindent
     {"local" nil
      :modifyLineBreaks false}
     :bibtexFormatter "texlab"
     :formatterLineLength 80}}})
