;; Startup profiling (must run before require is monkey-patched elsewhere)
(let [should-profile (os.getenv "NVIM_PROFILE")]
  (when should-profile
    (local prof (require :profile))
    (prof.instrument_autocmds)
    (local profile-mode (string.lower should-profile))
    (if (string.match profile-mode "^start")
        (do
          (prof.start "*")
          (vim.api.nvim_create_autocmd "VimEnter"
                                       {:once true
                                        :callback (fn []
                                                    (prof.stop)
                                                    (prof.export
                                                      "profile-startup.json")
                                                    (vim.notify
                                                      "Wrote profile-startup.json"))}))
        (if (string.match profile-mode "^statusline")
            (do
              ;; Ensure require is wrapped before other plugins monkey-patch it.
              (prof.instrument "config.statusline")
              (vim.api.nvim_create_autocmd "User"
                                           {:pattern "DeferredUIEnter"
                                            :once true
                                            :callback (fn []
                                                        (prof.start "config.statusline")
                                                        ;; DeferredUIEnter schedules the require; stop after it runs.
                                                        (vim.schedule
                                                          (fn []
                                                            (vim.schedule
                                                              (fn []
                                                                (prof.stop)
                                                                (prof.export
                                                                  "profile-statusline.json")
                                                                (vim.notify
                                                                  "Wrote profile-statusline.json"))))))}))
            (prof.instrument "*")))))

;; Trigger the lazy-loading of plugins on `require(...)` calls
((. (require :lzn-auto-require) :enable))

(require :config)
(require :plugins)
