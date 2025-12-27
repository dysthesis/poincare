(require-macros :lib.core)
(require-macros :lib.vim)

(g! :mapleader " ")

(set! :number true)
(set! :relativenumber true)
(set! :termguicolors true)

;; Trigger the lazy-loading of plugins on `require(...)` calls
((. (require :lzn-auto-require) :enable))

(require :plugins)
(require :config)
