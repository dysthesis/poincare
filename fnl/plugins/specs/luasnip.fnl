(require-macros :plugins.helpers)

(use "LuaSnip"
  :lazy false
  :after
  (fn []
    ;; Make sure snippet sources are on the runtimepath.
    (pcall vim.cmd "packadd luasnip")
    (pcall vim.cmd "packadd friendly-snippets")

    ;; `require "luasnip"` can be a loader function in our lazy setup; normalise
    ;; it to the real module table so downstream consumers (e.g. blink.cmp)
    ;; see the expected API. Disable lzn-auto-require while resolving so we run
    ;; the real module instead of getting a loadfile thunk back.
    (local pack
      (or (. table :pack)
          (fn [...]
            (local t [...])
            (set t.n (select "#" ...))
            t)))

    (let [lzn-res (pack (pcall require :lzn-auto-require))]
      (local ok-lzn (. lzn-res 1))
      (local lzn (. lzn-res 2))
      (when ok-lzn ((. lzn :disable)))

      ;; Capture results then allow mutation below.
      (local pcall-res (pack (pcall require :luasnip)))
      (var ok (. pcall-res 1))
      (var ls (. pcall-res 2))

      (when ok
        (when (= (type ls) :function)
          ;; Call loader placeholder to obtain the real module and cache it.
          (local pcall-res2 (pack (pcall ls)))
          (set ok (. pcall-res2 1))
          (set ls (. pcall-res2 2)))

        (when (and ok (= (type ls) :table))
          (set (. package.loaded :luasnip) ls)
          ((. (. ls :config) :setup)
           {:history true
            :updateevents "TextChanged,TextChangedI"
            :enable_autosnippets false})

          ((. (require :luasnip.loaders.from_vscode) :lazy_load))))

      (when ok-lzn ((. lzn :enable))))))
