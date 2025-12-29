;; config/ui.fnl
;; UI configuration and markdown cosmetics.

(require-macros :lib.vim)

(local api vim.api)
(local schedule (require :utils.schedule))

(set! :winborder "rounded")
(set! :termguicolors true)
(set! :laststatus 3)
(set! :number true)
(set! :relativenumber true)
(set! :conceallevel 2)
(g! :vim_markdown_conceal 1)
(set! :signcolumn "yes")
(set! :hlsearch true)
(set! :splitright true)
(set! :splitbelow true)
(set! :list true)
(set! :listchars {:tab "» " :trail "·" :nbsp "␣"})
(set! :inccommand "split")
(set! :cmdwinheight 20)
(set! :cursorline true)
(set! :scrolloff 10)

;; Markdown
(var bullet-symbol "•")

(fn set-bullet-symbol [symbol]
  (set bullet-symbol symbol))

;; keep the legacy global name for callers that expect it
(set _G.SetBulletSymbol set-bullet-symbol)

(fn update-extmarks [bufnr ns-id]
  (let [lines (api.nvim_buf_get_lines bufnr 0 -1 true)]
    (each [idx line (ipairs lines)]
      (let [lnum (- idx 1)]
        (when (string.match line "^%s*[-%*%+] ")
          (let [indent (string.match line "^%s*")]
            (api.nvim_buf_set_extmark
              bufnr
              ns-id
              lnum
              (# indent)
              {:end_col (+ (# indent) 1)
               :conceal bullet-symbol})))))))

(fn setup-extmarks-autocmd []
  (let [ns-id (api.nvim_create_namespace "MarkdownStyling")]
    (api.nvim_create_autocmd
      ["BufEnter" "TextChanged" "TextChangedI" "TextChangedP"]
      {:pattern "*.md"
       :callback (fn [ev] (update-extmarks ev.buf ns-id))})))

(schedule.group "markdown_styling"
  [{:events "VimEnter"
    :callback setup-extmarks-autocmd}])
