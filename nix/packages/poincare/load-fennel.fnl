(if (pcall require :hotpot)
    (do
      (local allowed-globals [])
      (each [k _ (pairs _G)] (table.insert allowed-globals k))
      ((. (require :hotpot) :setup) {:compiler {:modules {:correlate true :requireAsInclude true
                                                          :useBitLib true}
                                                :macros {:env :_COMPILER
                                                         :compilerEnv _G
                                                         :allowedGlobals allowed-globals}}
                                     :enable_hotpot_diagnostics true
                                     :build [{:verbose true}
                                             [:fnl/init.fnl true]]
                                     :provide_require_fennel true})
      (require :init))
      
    (vim.notify "Failed to load hotpot.nvim!" vim.log.levels.ERROR))
