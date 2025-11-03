;; This file defines configurations that are meant to be universal and immutable.
;; Only add them here if there is no reason to make them configurable.

(import-macros { : set!} :macros)
;; speedups
(set! updatetime 250)
(set! timeoutlen 400)
;; visual options
(set! conceallevel 2)
(set! infercase)
(set! shortmess+ :sWcI)
(set! signcolumn "yes:1")
(set! formatoptions [:q :j])
(set! nowrap)
;; just good defaults
(set! splitright)
(set! splitbelow)
;; tab options
(set! tabstop 4)
(set! shiftwidth 4)
(set! softtabstop 4)
(set! expandtab)
;; clipboard and mouse
(set! clipboard :unnamedplus)
(set! mouse :a)
;; backups are annoying
(set! undofile)
(set! nowritebackup)
(set! noswapfile)
;; external config files
(set! exrc)
;; search and replace
(set! ignorecase)
(set! smartcase)
(set! gdefault)
;; better grep
(set! grepprg "rg --vimgrep")
(set! grepformat "%f:%l:%c:%m")
(set! path ["." "**"])
;; previously nightly options
(set! diffopt+ "linematch:60")
(set! splitkeep :screen)
(set! list)
(set! fillchars {:eob " "
                 :vert " "
                 :horiz " "
                 :diff "╱"
                 :foldclose ""
                 :foldopen ""
                 :fold " "
                 :msgsep "─"})
(set! listchars {:tab " ──"
                 :trail "·"
                 :nbsp "␣"
                 :precedes "«"
                 :extends "»"})
(set! scrolloff 4)
(set! winborder "rounded")
(set! termguicolors true)
(set! number true)
(set! relativenumber true)
(set! hlsearch true)
(set! splitright true)
(set! splitbelow true)
