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

    ;; Define the formatters to use for each language
    (local formatter-spec
           {:lua [["stylua"]]
            :markdown [["markdownlint"]]
            :nix [["alejandra"]]
            :c [["clang-format"]]
            :rust [["rustfmt"]]
            :go [["go/fmt" "gofmt"]]
            :ocaml [["ocamlformat"]]})

    (fn available-formaters-by-ft [spec]
      "Filter out spec by whether the actual formatter binaries are found"
      (let [out {}]
        ;; Split the key and value of the spec
        (each [ft entries (pairs spec)]
          ;; Filter out the value by available formatters
          (let [formatters (formatters-if-available entries)]
            ;; Only add them if there are any in the first place
            (when (> (# formatters) 0)
              (tset out ft formatters))))))

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
