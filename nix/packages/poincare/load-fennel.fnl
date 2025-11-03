(if (pcall require :hotpot)
    (do
      ((. (require :hotpot) :setup)
       {:compiler
        {:modules {:correlate true :requireAsInclude true :useBitLib true}
         :macros  {:env :_COMPILER
                   :compilerEnv _G
                   :allowedGlobals false}}
        :enable_hotpot_diagnostics true
        :build [{:verbose true} [:fnl/init.fnl true]]
        :provide_require_fennel true})
      (require :init)
      (require :core))
    (vim.notify "Failed to load hotpot.nvim!" vim.log.levels.ERROR))
