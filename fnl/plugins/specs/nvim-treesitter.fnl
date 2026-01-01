(require-macros :plugins.helpers)

(use "nvim-treesitter"
  :lazy false
  :load
  (fn [name]
    (vim.cmd.packadd name)
    (when (not vim.g.poincare_ts_grammars_loaded)
      (set vim.g.poincare_ts_grammars_loaded true)
      (each [_ packpath (ipairs (vim.split vim.o.packpath "," {:plain true}))]
        (local pattern (.. packpath "/pack/*/opt/vimplugin-treesitter-grammar-*"))
        (each [_ path (ipairs (vim.fn.glob pattern false true))]
          (local plugin (vim.fn.fnamemodify path ":t"))
          (vim.cmd.packadd plugin)))))

  :after
  (fn []
    ((. (require :nvim-treesitter) :setup)
     {:install_dir (.. (vim.fn.stdpath "data") "/site")})
    (vim.api.nvim_create_autocmd 
      "FileType" {:pattern "*"
                  :callback (fn [ev]
                              (when (pcall vim.treesitter.start ev.buf)
                                (tset 
                                  (. (. vim.wo 0) 0) 
                                  :foldexpr "v:lua.vim.treesitter.foldexpr()")
                                (tset (. (. vim.wo 0) 0) :foldmethod "expr")))})
    (vim.api.nvim_create_autocmd 
      "FileType" {:pattern ["lua"
                            "rust"
                            "zig" 
                            "c" 
                            "cpp" 
                            "go" 
                            "nix" 
                            "python" 
                            "fennel" 
                            "ocaml"]
      :callback (fn [ev]
                  (tset (. vim.bo ev.buf) :indentexpr
                        "v:lua.require'nvim-treesitter'.indentexpr()"))})))
