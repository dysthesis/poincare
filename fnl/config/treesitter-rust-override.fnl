(local M {})

;; Some third-party highlight additions reference the `identifier_pattern` node
;; that is absent from the Rust grammar version shipped with our pinned
;; nvim-treesitter. When Neovim concatenates those queries, parsing fails and
;; downstream consumers (blink.cmp decorators) error out. To keep things stable,
;; we preemptively override the Rust highlights query with the base
;; nvim-treesitter version, skipping any incompatible additions found later on
;; the runtimepath.
(fn M.override-rust-highlights []
  (local files (vim.treesitter.query.get_files "rust" "highlights"))
  (when (and files (> (# files) 0))
    ;; Prefer the canonical nvim-treesitter query and avoid colour-scheme
    ;; addenda that may require a newer grammar (e.g. minimal.nvim).
    (var base nil)
    (each [_ path (ipairs files)]
      (when (and (not base) (not (string.find path "minimal.nvim")))
        (set base path)))
    (set base (or base (. files 1)))

    (local (ok content)
      (pcall
        (fn []
          (table.concat (vim.fn.readfile base) "\n"))))

    (when ok
      (pcall vim.treesitter.query.set "rust" "highlights" content))))

(M.override-rust-highlights)

M
