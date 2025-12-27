;; Startup profiling (must run before require is monkey-patched elsewhere)
(let [should-profile (os.getenv "NVIM_PROFILE")]
  (when should-profile
    (local prof (require :profile))
    (prof.instrument_autocmds)
    (if (string.match (string.lower should-profile) "^start")
        (do
          (prof.start "*")
          (vim.api.nvim_create_autocmd "VimEnter"
                                       {:once true
                                        :callback (fn []
                                                    (prof.stop)
                                                    (prof.export "profile-startup.json")
                                                    (vim.notify "Wrote profile-startup.json"))}))
        (prof.instrument "*"))))

;; Trigger the lazy-loading of plugins on `require(...)` calls
((. (require :lzn-auto-require) :enable))

(require :config)
(require :plugins)
