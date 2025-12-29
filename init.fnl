;; Trigger the lazy-loading of plugins on `require(...)` calls
((. (require :lzn-auto-require) :enable))

(require :config)
(require :plugins)
