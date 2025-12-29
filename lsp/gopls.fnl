;; lsp/gopls.fnl

(var mod-cache nil)
(var std-lib nil)
(local lsp (require :utils.lsp))

(fn identify-go-dir [custom-args on-complete]
  (let [cmd ["go" "env" (. custom-args :envvar_id)]]
    (vim.system cmd {:text true}
      (fn [output]
        (let [res (vim.trim (or output.stdout ""))]
          (if (and (= output.code 0) (not= res ""))
              (let [subdir (?. custom-args :custom_subdir)
                    resolved (if (and subdir (not= subdir ""))
                                 (.. res subdir)
                                 res)]
                (on-complete resolved))
              (do
                (vim.schedule
                  (fn []
                    (vim.notify
                      (string.format
                        "[gopls] identify %s dir cmd failed with code %d: %s\n%s"
                        (. custom-args :envvar_id)
                        output.code
                        (vim.inspect cmd)
                        (or output.stderr "")))))
                (on-complete nil))))))))

(fn get-std-lib-dir []
  (if (and std-lib (not= std-lib ""))
      std-lib
      (do
        (identify-go-dir
          {:envvar_id "GOROOT" :custom_subdir "/src"}
          (fn [dir]
            (when (and dir (not= dir ""))
              (set std-lib dir))))
        std-lib)))

(fn get-mod-cache-dir []
  (if (and mod-cache (not= mod-cache ""))
      mod-cache
      (do
        (identify-go-dir
          {:envvar_id "GOMODCACHE"}
          (fn [dir]
            (when (and dir (not= dir ""))
              (set mod-cache dir))))
        mod-cache)))

(fn get-root-dir [fname]
  (let [fallback
        (or (vim.fs.root fname "go.work")
            (vim.fs.root fname "go.mod")
            (vim.fs.root fname ".git"))
        current-root
        (let [clients (vim.lsp.get_clients {:name "gopls"})]
          (when (> (# clients) 0)
            (?. (. clients (# clients)) :config :root_dir)))]
    (if (and mod-cache (= (fname:sub 1 (# mod-cache)) mod-cache))
        (or current-root fallback)
        (if (and std-lib (= (fname:sub 1 (# std-lib)) std-lib))
            (or current-root fallback)
            fallback))))

(lsp.server
  {:cmd ["gopls"]
   :filetypes ["go" "gomod" "gowork" "gotmpl"]
   :root_dir
   (fn [bufnr on-dir]
     (let [fname (vim.api.nvim_buf_get_name bufnr)]
       (get-mod-cache-dir)
       (get-std-lib-dir)
       ;; see: https://github.com/neovim/nvim-lspconfig/issues/804
       (on-dir (get-root-dir fname))))})
