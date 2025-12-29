(require-macros :plugins.helpers)

(use "nvim-lint"
  :event ["BufReadPre" "BufNewFile"]
  :after
  (fn []
    (local lint (require :lint))

    (fn zlint-parser [output bufnr]
      (local items [])
      ;; get buffer by file name
      (each [_ line (ipairs (vim.split output "\n" {:plain true}))]
        (local (level file row col message)
          (line:match "::(%w+)%sfile=([^,]+),line=(%d+),col=(%d+),title=(.*)"))
        (local severity
          (case level
            "error" vim.diagnostic.severity.ERROR
            "warning" vim.diagnostic.severity.WARN
            _ nil))

        (when (and file severity)
          (local l-bufnr (vim.fn.bufnr file))
          (when (and (> l-bufnr -1) (= l-bufnr bufnr))
            (table.insert items
              {:lnum (- (tonumber row) 1)
               :col (- (tonumber col) 1)
               :message message
               :source "zlint"
               :bufnr bufnr
               :severity severity}))))
      items)

    (set lint.linters.zlint
      {:name "zlint"
       :cmd "zlint"
       :stdin false
       :append_fname false
       :args ["-f" "gh"]
       :stream "both"
       :ignore_exitcode true
       :parser zlint-parser})

    (fn linters-if-available [entries]
      "Add linters if the binary is discoverable. This is to prevent annoying
      errors when they are not."
      (local acc [])
      (each [_ entry (ipairs entries)]
        (let [linter (. entry 1)
              cmd (or (. entry 2) linter)]
          (when (= 1 (vim.fn.executable cmd))
            (table.insert acc linter))))
      acc)

    (fn prune-empty [ft-map]
      (local out {})
      (each [ft linters (pairs ft-map)]
        (when (> (# linters) 0)
          (tset out ft linters)))
      out)

    (local linters-by-ft
      (prune-empty
        {:zig (linters-if-available [["zlint"]])
         :rust (linters-if-available [["clippy" "cargo"]])
         :nix (linters-if-available [["deadnix" "statix"]])
         :markdown (linters-if-available [["vale"]])}))

    (set lint.linters_by_ft linters-by-ft)

    (local lint-augroup (vim.api.nvim_create_augroup "lint" {:clear true}))
    (vim.api.nvim_create_autocmd ["BufEnter" "BufWritePost" "InsertLeave"]
      {:group lint-augroup
       :callback
       (fn []
         ;; Only run the linter in buffers that you can modify in order to
         ;; avoid superfluous noise, notably within the handy LSP pop-ups that
         ;; describe the hovered symbol using Markdown.
        (when (vim.opt_local.modifiable:get)
          ((. lint :try_lint))))})
    ))
