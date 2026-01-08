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

    (local formatter-spec
      {:lua [["stylua"]]
      :markdown [["markdownlint"]]
      :nix [["alejandra"]]
      :c [["clang-format"]]
      :rust [["rustfmt"]]
      :go [["gofmt"]]
      :ocaml [["ocamlformat"]]})

    (fn available-formaters-by-ft [spec]
      "Filter out spec by whether the actual formatter binaries are found"
      (let [out {}]
        (each [ft entries (pairs spec)]
          (let [formatters (formatters-if-available entries)]
            (when (> (# formatters) 0)
              (tset out ft formatters))))
        out))

    ;; Disable "format_on_save" LSP fallback for filetypes that do not have a
    ;; well standardised coding style. Add filetypes to disable, or remove
    ;; them to re-enable.
    (local disable-filetypes {})

    ;; Enable formatting on save unless defined otherwise.
    (fn format-on-save [bufnr]
      {:timeout_ms 500
       :lsp_fallback (not (. disable-filetypes (. vim.bo bufnr :filetype)))})

    ((. conform :setup)
     {:notify_on_error false
      :format_on_save format-on-save
      :format_after_save {:async true}
      :formatters_by_ft (available-formaters-by-ft formatter-spec)
      :formatters
      {:ocamlformat
       {:prepend_args ["--if-then-else" "vertical"
                       "--break-cases" "fit-or-vertical"
                       "--type-decl" "sparse"]}}})))
