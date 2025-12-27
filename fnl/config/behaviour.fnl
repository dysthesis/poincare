;; config/behaviour.fnl
;; Core editor behaviour and defaults.

(require-macros :lib.vim)

(local api vim.api)
(local vfn vim.fn)
(local opt vim.opt)
(local schedule (require :utils.schedule))

;; Set to true if you have a Nerd Font installed and selected in the terminal.
(g! :have_nerd_font true)
(g! :mapleader " ")
(g! :maplocalleader " ")

(set! :compatible false)
(set! :colorcolumn "80")
(set! :mouse "a")
(set! :showmode false)
(set! :clipboard "unnamedplus")
(set! :breakindent true)
(set! :undofile true)
(set! :ignorecase true)
(set! :smartcase true)
(set! :smartindent true)
(set! :sidescrolloff 8)
(set! :signcolumn "yes")
(set! :termguicolors true)
(set! :wrap true)
(set! :updatetime 250)
(set! :jumpoptions "view")
(set! :pumblend 10)
(set! :pumheight 10)
(set! :scrolloff 4)
(set! :shiftround true)
(set! :softtabstop 2)
(set! :tabstop 2)
(set! :shiftwidth 2)

(set! :sessionoptions
  ["buffers" "curdir" "tabpages" "winsize" "help" "globals" "skiprtp" "folds"])

(set! :grepprg "rg --glob \"!.git\" --no-heading --vimgrep --follow $*")
(set^ :grepformat "%f:%l:%c:%m")
(set! :wildoptions "fuzzy,pum,tagfile")
(setlocal! :omnifunc "v:lua.vim.lsp.omnifunc")

(set! :completeopt ["menu" "menuone" "noselect"])
(fn try-append [opt-obj val]
  (pcall (fn [] (opt-obj:append val))))
(try-append opt.completeopt "popup")
(try-append opt.completeopt "fuzzy")

;; Filetype extensions and patterns that should be available before plugins load.
(vim.filetype.add
  {:pattern {".*/hypr/.*%.conf" "hyprlang"}
   :extension {:sage "python"}})

(let [nvim-010? (= 1 (vfn.has "nvim-0.10"))]
  (set! :foldcolumn (if nvim-010? "1" 1))
  (if nvim-010?
      (do (set! :smoothscroll true)
          (set! :foldtext ""))
      (set! :foldmethod "indent")))

;; Fold by treesitter expression.
(let [tsq (require :vim.treesitter.query)
      zig-folds
      (table.concat
        [";; Match the { ... } block whose *parent* is a function-like node."
         "((block) @fold"
         "  (#has-parent? @fold \"function_declaration\"))"
         ""
         ";; Back-compat for parsers that name it `fn_decl`."
         "((block) @fold"
         "  (#has-parent? @fold \"fn_decl\"))"]
        "\n")
      rust-folds
      (table.concat
        ["(block) @fold"
         "(#has-parent? @fold \"function_item\")"]
        "\n")
      c-folds
      (table.concat
        ["(function_definition"
         "  body: (compound_statement) @fold)"]
        "\n")]
  (tsq.set "zig" "folds" zig-folds)
  (tsq.set "rust" "folds" rust-folds)
  (tsq.set "c" "folds" c-folds))

(rem! :viewoptions "folds")
(set! :foldenable true)
(set! :foldlevel 99)
(set! :foldlevelstart 99)
(set! :expandtab true)

(set! :fillchars
  {:foldopen ""
   :foldclose ""
   :fold " "
   :foldsep " "
   :diff "╱"
   :eob " "})

(local abbrevs
  [["W!" "w!"]
   ["Q!" "q!"]
   ["Qall!" "qall!"]
   ["Wq" "wq"]
   ["Wa" "wa"]
   ["wQ" "wq"]
   ["WQ" "wq"]
   ["W" "w"]
   ["Q" "q"]])

(fn cnoreabbrev [from to]
  (vim.cmd (.. "cnoreabbrev " from " " to)))

(each [_ pair (ipairs abbrevs)]
  (let [[from to] pair]
    (cnoreabbrev from to)))

(schedule.group "general"
  [{:events "BufReadPost"
    :opts {:desc "Restore last cursor position in file"}
    :callback
    (fn []
      (let [pos (vfn.line "'\"")
            last (vfn.line "$")]
        (when (and (> pos 0) (<= pos last))
          (vfn.setpos "." (vfn.getpos "'\"")))))}
   {:events ["VimResized"]
    :opts {:desc "Resize all splits if vim was resized"}
    :callback (fn [] (vim.cmd.tabdo "wincmd ="))}])

(local ignore-filetypes ["gitcommit" "gitrebase" "svg" "hgcommit"])

(fn view-eligible? [buf]
  (let [filetype (api.nvim_get_option_value "filetype" {:buf buf})
        buftype (api.nvim_get_option_value "buftype" {:buf buf})]
    (and (= buftype "")
         filetype
         (not= filetype "")
         (not (vim.tbl_contains ignore-filetypes filetype)))))

(fn save-view [buf]
  (let [vars (. vim.b buf)]
    (when (and vars (. vars :view_activated))
      (vim.cmd.mkview {:mods {:emsg_silent true}}))))

(fn ensure-view-active [buf]
  (let [vars (. vim.b buf)]
    (when (and vars (not (. vars :view_activated)) (view-eligible? buf))
      (set vars.view_activated true)
      (vim.cmd.loadview {:mods {:emsg_silent true}}))))

(schedule.group "auto_view"
  [{:events ["BufWinLeave" "BufWritePost" "WinLeave"]
    :opts {:desc "Save view with mkview for real files"}
    :callback (fn [args] (save-view args.buf))}
   {:events "BufWinEnter"
    :opts {:desc "Try to load file view if available and enable view saving for real files"}
    :callback (fn [args] (ensure-view-active args.buf))}]
  {:clear true})

;; Let sqlite.lua know where to find sqlite.
(local luv (require :luv))
(g! :sqlite_clib_path (luv.os_getenv "LIBSQLITE"))
