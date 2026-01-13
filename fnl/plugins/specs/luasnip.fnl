(require-macros :plugins.helpers)

;; Capture multiple return values without relying on table.pack.
(local pack
  (fn [...]
    (local t [...])
    (set t.n (select "#" ...))
    t))

;; Resolve the real LuaSnip module table, handling loader placeholders and
;; temporarily disabling lzn-auto-require to avoid loadfile thunks.
(fn resolve-luasnip []
  (var ok false)
  (var ls nil)

  (let [lzn-res (pack (pcall require :lzn-auto-require))]
    (local ok-lzn (. lzn-res 1))
    (local lzn (. lzn-res 2))
    (when ok-lzn ((. lzn :disable)))

    (let [res (pack (pcall require :luasnip))]
      (set ok (. res 1))
      (set ls (. res 2)))

    (when (and ok (= (type ls) :function))
      (let [res2 (pack (pcall ls))]
        (set ok (. res2 1))
        (set ls (. res2 2))))

    (when ok-lzn ((. lzn :enable))))

  (and ok (= (type ls) :table) ls))

(use "LuaSnip"
  :lazy false
  :after
  (fn []
    ;; Make sure snippet sources are on the runtimepath.
    (pcall vim.cmd "packadd luasnip")
    (pcall vim.cmd "packadd friendly-snippets")

    (let [ls (resolve-luasnip)]
      (when ls
        (set (. package.loaded :luasnip) ls)
        ((. (. ls :config) :setup)
         {:history true
          :updateevents "TextChanged,TextChangedI"
          :enable_autosnippets false})
        ((. (require :luasnip.loaders.from_vscode) :lazy_load))))))
