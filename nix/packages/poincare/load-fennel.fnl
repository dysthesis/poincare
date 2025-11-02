;; Can we load hotpot
(if (pcall require :hotpot) 
  (do ((. (require "hotpot") "setup") {:compiler {:macros {:allowGlobals true :compilerEnv _G :env "_COMPILER"}}
                                              :modules {:correlate true :useBitLib true}}
                                   :enable_hotpot_diagnostics true
                                   :build [{:verbose true} [:init.fnl true]]
                                   :provide_require_fennel true) 
    (require :init))
  ;; No? We have to fail, then.
  (vim.notify "Failed to load hotpot.nvim!" vim.log.levels.ERROR))
