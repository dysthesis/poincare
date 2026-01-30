(require-macros :plugins.helpers)
(require-macros :plugins.helpers)

;; Define where notes are stored at
(local home (vim.fn.expand "~"))
(local path (.. home "/Documents/Notes"))

(use "zk-nvim"
     :event [(.. "BufReadPre " path "**.md")
             (.. "BufNewFile " path "/**.md")]
     :keys [(keymap "<S-CR>"
                    (vim.lsp.buf.definition)
                    "Follow link")
            (keymap "C-CR"
                    ":'<,'>ZkNewFromTitleSelection { dir = vim.fn.expand('%:p:h') }<CR>"
                    "New note from selection")
            (keymap "<leader>nn"
                    "<Cmd>ZkNew { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>"
                    "[N]ote [N]ew")
            (keymap "<leader>nnt"
                    ":'<,'>ZkNewFromTitleSelection { dir = vim.fn.expand('%:p:h') }<CR>"
                    "[N]ew [N]ote from [T]itle")
            (keymap "<leader>nnc"
                    ":'<,'>ZkNewFromContentSelection { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>"
                    "[N]ew [N]ote from [C]ontent")
            (keymap "<leader>nb"
                    "<CMD>ZkBacklinks<CR>"
                    "[N]ote [B]acklinks")
            (keymap "<leader>nl"
                    "<CMD>ZkLinks<CR>"
                    "[N]ote [L]inks")
            (keymap "<leader>nf"
                    (fn []
                      (local zk (require :zk))
                      (zk.edit {:tags ["NOT literature"
                                       "NOT journal"
                                       "NOT fleeting"]
                                :title "Notes"}))
                    "[N]ote [F]ind")
            (keymap "<leader>nF"
                    (fn []
                      (local zk (require :zk))
                      (zk.edit {:tags ["fleeting"]
                                :title "Fleeting"}))
                    "[N]ote [F]leeting")
            (keymap "<leader>nL"
                    (fn []
                      (local zk (require :zk))
                      (zk.edit {:tags ["literature"]
                                :title "Literature"}))
                    "[N]ote [L]iterature")
            (keymap "<leader>nj"
                    (fn []
                      (local zk (require :zk))
                      (zk.edit {:tags ["journal"]
                                :title "Journal"}))
                    "[N]ote [J]ournal")
            (keymap "<leader>nt"
                    "<CMD>ZkTags<CR>"
                    "[N]ote [T]ags")]
     :before (fn []
               (local lzn (require :lz.n))
               (lzn.trigger_load :mini.pick))
     :after (fn []
              (local zk (require :zk))
              (zk.setup {:picker "minipick"})))
