;; config/statusline.fnl
;;
;; Plugin-less status-bar configuration. This was originally taken from
;; https://github.com/shivambegin/Neovim/blob/a1b6009501f88dcc82d4fc681bb28dc2ab781d77/lua/config/statusline.lua

(local api vim.api)
(local vfn vim.fn)

(var prof nil)
(local profile-mode (os.getenv "NVIM_PROFILE"))
(local profile-ok false)

;; Default to no-ops unless profiling is explicitly enabled.
(var prof-start (fn [_] nil))
(var prof-end (fn [_] nil))

(when profile-mode
  (set profile-ok
       (pcall
         (fn []
           (set prof (require :profile)))))
  (when (and profile-ok prof)
    (set prof-start
         (fn [label]
           (when (prof.is_recording)
             (prof.log_start label))))
    (set prof-end
         (fn [label]
           (when (prof.is_recording)
             (prof.log_end label))))))

(var mini-icons nil)

(fn ensure-mini-icons []
  (when (not mini-icons)
    (local global-icons (rawget _G :MiniIcons))
    (when (= (type global-icons) :table)
      (set mini-icons global-icons)))
  mini-icons)

(prof-start "config.statusline.load")

(local statusline-augroup (api.nvim_create_augroup "native_statusline" {:clear true}))

(local statusline-bg "#080808")

(fn with-bg [opts]
  ;; produce a fresh table so we do not accidentally mutate a shared one
  (vim.tbl_extend "force" {:bg statusline-bg} opts))

(local highlight-spec
  [;; defaults
   ["StatusLine"              {:fg "#ffffff"}]
   ["StatusLineNC"            {:fg "#565f89"}]

   ;; custom groups
   ["StatusLineModeBold"      {:fg "#ffffff" :bold true}]
   ["StatusLineMode"          {:fg "#ffffff"}]
   ["StatusLineMedium"        {:fg "#444444"}]
   ["StatusLineLspActive"     {:fg "#789978"}]
   ["StatusLineLspError"      {:fg "#ffaa88"}]
   ["StatusLineLspWarn"       {:fg "#ffaa88"}]
   ["StatusLineLspHint"       {:fg "#7788aa"}]
   ["StatusLineLspInfo"       {:fg "#0db9d7"}]
   ["StatusLineLspMessages"   {:fg "#a9b1d6"}]
   ["StatusLineGitDiffAdded"  {:fg "#789978"}]
   ["StatusLineGitDiffChanged" {:fg "#708090"}]
   ["StatusLineGitDiffRemoved" {:fg "#ffaa88"}]
   ["StatusLineGitBranchIcon" {:fg "#444444"}]])

(fn setup-highlights []
  (each [_ spec (ipairs highlight-spec)]
    (let [[group opts] spec]
      (api.nvim_set_hl 0 group (with-bg opts)))))

(prof-start "statusline.autocmds")
(api.nvim_create_autocmd "ColorScheme"
  {:group statusline-augroup
   :callback setup-highlights})

(prof-start "statusline.setup-highlights")
(setup-highlights)
(prof-end "statusline.setup-highlights")

(fn hl [group s]
  ;; NOTE: this is a statusline string, so we keep raw % characters.
  (.. "%#" group "#" s "%*"))

(local space (hl "StatusLineMedium" " "))

(fn nonempty? [s] (and s (not= s "")))

(fn filename []
  (let [fname (vfn.expand "%:t")]
    (if (nonempty? fname) (.. fname " ") "")))

(fn get-lsp-diagnostics-count [severity]
  (if (not (rawget vim :lsp))
      0
      (let [counts (vim.diagnostic.count 0 {:severity severity})
            n      (. counts severity)]
        (or n 0))))

(fn get-git-diff [kind]
  (let [gsd vim.b.gitsigns_status_dict]
    (if (and gsd (. gsd kind))
        (. gsd kind)
        0)))

(local modes
  {:n   "NOR"
   :no  "NOR"
   :v   "VIS"
   :V   "VISUAL LINE"
   ;; visual block / select block are control chars; these escapes are portable:
   ;; "\022" is Ctrl-V, "\019" is Ctrl-S
   "\022" "VISUAL BLOCK"
   :s   "SEL"
   :S   "SELECT LINE"
   "\019" "SELECT BLOCK"
   :i   "INS"
   :ic  "INS"
   :R   "REPLACE"
   :Rv  "VISUAL REPLACE"
   :c   "COMMAND"
   :cv  "VIM EX"
   :ce  "EX"
   :r   "PROMPT"
   :rm  "MOAR"
   "r?" "CONFIRM"
   :!   "SHELL"
   :t   "TERMINAL"})

(fn mode []
  (let [m (. (api.nvim_get_mode) :mode)
        label (or (. modes m) m)]
    (hl "StatusLineModeBold" (.. " " (string.upper label) " "))))

(fn lsp-clients []
  (let [buf (api.nvim_get_current_buf)
        clients (if (rawget vim :lsp) (vim.lsp.get_clients {:bufnr buf}) nil)]
    (if (or (not clients) (= (next clients) nil))
        ""
        (let [names []]
          (each [_ c (pairs clients)]
            (table.insert names c.name))
          (.. " "
              (hl "StatusLineGitBranchIcon" "󰌘 ")
              (hl "StatusLineMedium" (table.concat names "|")))))))

(fn lsp-active []
  (if (not (rawget vim :lsp))
      ""
      (let [buf (api.nvim_get_current_buf)
            clients (vim.lsp.get_clients {:bufnr buf})]
        (if (> (# clients) 0)
            (.. space (hl "StatusLineLspActive" " ") "LSP")
            ""))))

(fn diagnostics-error []
  (let [n (get-lsp-diagnostics-count vim.diagnostic.severity.ERROR)]
    (if (> n 0) (hl "StatusLineLspError" (.. "  " n)) "")))

(fn diagnostics-warn []
  (let [n (get-lsp-diagnostics-count vim.diagnostic.severity.WARN)]
    (if (> n 0) (hl "StatusLineLspWarn" (.. "  " n)) "")))

(fn diagnostics-hint []
  (let [n (get-lsp-diagnostics-count vim.diagnostic.severity.HINT)]
    (if (> n 0) (hl "StatusLineLspHint" (.. "  " n)) "")))

(fn diagnostics-info []
  (let [n (get-lsp-diagnostics-count vim.diagnostic.severity.INFO)]
    (if (> n 0) (hl "StatusLineLspInfo" (.. "  " n)) "")))

(var lsp-progress
  {:client nil :kind nil :title nil :percentage nil :message nil})

(api.nvim_create_autocmd "LspProgress"
  {:group statusline-augroup
   :desc "Update LSP progress in statusline"
   :pattern ["begin" "report" "end"]
   :callback
   (fn [args]
     (let [data (. args :data)]
       (when (and data (. data :client_id) (. data :params) (?. data :params :value))
         (let [val (?. data :params :value)]
           (set lsp-progress
                {:client (vim.lsp.get_client_by_id (. data :client_id))
                 :kind (?. val :kind)
                 :message (?. val :message)
                 :percentage (?. val :percentage)
                 :title (?. val :title)})
           (if (= lsp-progress.kind "end")
               (do (set lsp-progress.title nil)
                   (vim.defer_fn
                     (fn [] (vim.cmd.redrawstatus))
                     500))
               (vim.cmd.redrawstatus))))))})

;; -------------------- ;;
;;       git bits       ;;
;; -------------------- ;;

(fn git-diff-added []
  (let [n (get-git-diff "added")]
    (if (> n 0) (hl "StatusLineGitDiffAdded" (.. "  " n)) "")))

(fn git-diff-changed []
  (let [n (get-git-diff "changed")]
    (if (> n 0) (hl "StatusLineGitDiffChanged" (.. "  " n)) "")))

(fn git-diff-removed []
  (let [n (get-git-diff "removed")]
    (if (> n 0) (hl "StatusLineGitDiffRemoved" (.. "  " n)) "")))

(fn git-branch-icon [] (hl "StatusLineGitBranchIcon" ""))

(fn git-branch []
  (let [b vim.b.gitsigns_head]
    (if (nonempty? b) (hl "StatusLineMedium" b) "")))

(fn full-git []
  (let [parts []
        b (git-branch)]
    (when (nonempty? b)
      (table.insert parts space)
      (table.insert parts (git-branch-icon))
      (table.insert parts space)
      (table.insert parts b)
      (table.insert parts space))
    (let [a (git-diff-added) c (git-diff-changed) r (git-diff-removed)]
      (when (nonempty? a) (table.insert parts a))
      (when (nonempty? c) (table.insert parts c))
      (when (nonempty? r) (table.insert parts r)))
    (table.concat parts)))

;; -------------------- ;;
;;    position bits     ;;
;; -------------------- ;;

(fn file-percentage []
  (let [cur (. (api.nvim_win_get_cursor 0) 1)
        total (api.nvim_buf_line_count 0)
        denom (math.max total 1)
        pct (math.ceil (* (/ cur denom) 100))]
    ;; to display a literal percent sign in statusline, you need "%%"
    (hl "StatusLineMedium" (.. "  " pct "%% "))))

(fn total-lines []
  (let [row (vfn.line ".")
        col (vfn.col ".")
        total (vfn.line "$")]
    (hl "StatusLineMedium" (.. row ":" col " of " total " "))))

(fn formatted-filetype [group]
  (let [ft (or vim.bo.filetype (vfn.expand "%:e" false))]
    (hl group (.. " " ft " "))))

(fn filetype []
  (let [ft vim.bo.filetype
        MiniIcons (ensure-mini-icons)]
    (if (and MiniIcons (= (type MiniIcons) :table) (. MiniIcons :get))
        (let [(icon icon-hl _) (MiniIcons.get "filetype" ft)]
          (if (and icon icon-hl)
              ;; matches the Lua: icon highlight, then StatuslineTitle for the name
              (.. " " "%#" icon-hl "#" icon " " "%#StatuslineTitle#" ft)
              (hl "StatusLineMode" (.. " " ft " "))))
        (hl "StatusLineMode" (.. " " ft " ")))))

(fn lint-progress []
  (let [linters ((. (require "lint") :get_running))]
    (if (= (# linters) 0)
        "󰦕"
        (.. "󱉶 " (table.concat linters ", ")))))

;; keep optional segments referenced even when disabled in StatusLine.active
(do lsp-clients
    lsp-active
    diagnostics-error
    diagnostics-warn
    diagnostics-hint
    diagnostics-info
    lint-progress)

(local readable-filetypes
  {:qf true :help true :tsplayground true})

(local StatusLine {})

(set StatusLine.inactive
  (fn []
    (table.concat [(formatted-filetype "StatusLineMode")])))

(set StatusLine.active
  (fn []
    (let [m (. (api.nvim_get_mode) :mode)]
      (if (or (= m "t") (= m "nt"))
          (table.concat
            [(mode) "%=" "%=" (file-percentage) (total-lines)])
          (if (or (. readable-filetypes vim.bo.filetype) (= vim.o.modifiable false))
              (table.concat
                [(formatted-filetype "StatusLineMode") "%=" "%=" (file-percentage) (total-lines)])
              (table.concat
                [(mode)
                 (filename)
                 (full-git)
                 ;; (lsp-active)
                 ;; (diagnostics-error) (diagnostics-warn) (diagnostics-hint) (diagnostics-info)
                 ;; (lsp-clients)
                 "%=" "%="
                 (file-percentage)
                 (total-lines)
                 (filetype)]))))))

;; make it visible to v:lua.StatusLine.*
(set _G.StatusLine StatusLine)

;; global default
(prof-start "statusline.set-option")
(set vim.opt.statusline "%!v:lua.StatusLine.active()")
(prof-end "statusline.set-option")

;; filetypes/windows which should always use the inactive line
(api.nvim_create_autocmd ["WinEnter" "BufEnter" "FileType"]
  {:group statusline-augroup
   :pattern ["NvimTree_1" "NvimTree" "TelescopePrompt" "fzf" "lspinfo" "lazy"
             "netrw" "mason" "noice" "qf"]
   :callback (fn []
               (set vim.opt_local.statusline "%!v:lua.StatusLine.inactive()"))})

;; If you prefer requiring this as a normal module, you may also:
;; (return StatusLine)

(prof-end "statusline.autocmds")
(prof-end "config.statusline.load")
