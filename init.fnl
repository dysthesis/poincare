(require-macros :lib.core)
(require-macros :lib.vim)

(g! :mapleader " ")

(set! :number true)
(set! :relativenumber true)
(set! :termguicolors true)

(fn greet []
  (vim.notify "hello from fennel!"))

(map! [n] :gH `greet "Greets the world")
(command! [:nargs 0] :FennelGreet `greet)
