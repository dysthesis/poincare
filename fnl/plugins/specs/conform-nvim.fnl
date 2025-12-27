(require-macros :plugins.helpers)

(use "conform.nvim"
  :event "BufWritePre"
  :after
  (fn []
    (local conform (require :conform))

    (fn formatters-if-available [entries]
      "Add formatters if the binary is discoverable. This is to prevent annoying
      errors when they are not."
      (local acc [])
      (each [_ entry (ipairs entries)]
        (let [formatter (. entry 1)
              cmd (or (. entry 2) formatter)]
          (when (= 1 (vim.fn.executable cmd))
            (table.insert acc formatter))))
      acc)

    (fn prune-empty [ft-map]
      (local out {})
      (each [ft formatters (pairs ft-map)]
        (when (> (# formatters) 0)
          (tset out ft formatters)))
      out)

    ;; Disable "format_on_save" LSP fallback for filetypes that do not have a
    ;; well standardised coding style. Add filetypes to disable, or remove
    ;; them to re-enable.
    (local disable-filetypes {})

    (fn format-on-save [bufnr]
      {:timeout_ms 500
       :lsp_fallback (not (. disable-filetypes (. vim.bo bufnr :filetype)))})

    (local formatters-by-ft
      (prune-empty
        {:lua (formatters-if-available [["stylua"]])
         :markdown (formatters-if-available [["markdownlint"]])
         :nix (formatters-if-available [["alejandra"]])
         :c (formatters-if-available [["clang-format"]])
         :rust (formatters-if-available [["rustfmt"]])
         :go (formatters-if-available [["go/fmt" "gofmt"]])
         :ocaml (formatters-if-available [["ocamlformat"]])}))

    ((. conform :setup)
     {:notify_on_error false
      :format_on_save format-on-save
      :format_after_save {:async true}
      :formatters_by_ft formatters-by-ft
      :formatters
      {:ocamlformat
       {:prepend_args ["--if-then-else" "vertical"
                       "--break-cases" "fit-or-vertical"
                       "--type-decl" "sparse"]}}})))
