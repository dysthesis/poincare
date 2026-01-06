;; config/complexity.fnl

(local api vim.api)
(local schedule (require :utils.schedule))

(local default-opts
  {:enabled true
   :min 2
   :debounce_ms 150
   :prefix "Complexity "
   :hl_group "CyclomaticHint"
   :hl_groups {:low "CyclomaticHintLow"
               :medium "CyclomaticHintMedium"
               :high "CyclomaticHintHigh"}
   :severity_thresholds {:medium 6
                         :high 11}
   :virt_text_pos "right_align"
   :max_lines 20000})

(local user-opts
  (if (= (type vim.g.poincare_complexity) :table)
      vim.g.poincare_complexity
      {}))

(local opts (vim.tbl_extend "force" default-opts user-opts))

(when opts.enabled
  (when opts.hl_group
    (api.nvim_set_hl 0 opts.hl_group {:fg "#7788aa"}))
  (when (and (= (type opts.hl_groups) :table) opts.hl_groups)
    (when (. opts.hl_groups :low)
      (api.nvim_set_hl 0 (. opts.hl_groups :low) {:fg "#6c8a5b"}))
    (when (. opts.hl_groups :medium)
      (api.nvim_set_hl 0 (. opts.hl_groups :medium) {:fg "#b98b35"}))
    (when (. opts.hl_groups :high)
      (api.nvim_set_hl 0 (. opts.hl_groups :high) {:fg "#c25a5a"}))))

(local ns-id (api.nvim_create_namespace "CyclomaticComplexity"))
(var seq 0)
(local pending {})

(fn normalize-buf [bufnr]
  (if (or (not bufnr) (= bufnr 0))
      (api.nvim_get_current_buf)
      bufnr))

(fn clear-marks [bufnr]
  (local buf (normalize-buf bufnr))
  (when (api.nvim_buf_is_valid buf)
    (api.nvim_buf_clear_namespace buf ns-id 0 -1)))

(fn buf-eligible? [bufnr]
  (let [buf (normalize-buf bufnr)]
    (and (api.nvim_buf_is_valid buf)
         (= (api.nvim_get_option_value "buftype" {:buf buf}) "")
         (= (api.nvim_get_option_value "modifiable" {:buf buf}) true)
         (not= (api.nvim_get_option_value "filetype" {:buf buf}) "")
         (<= (api.nvim_buf_line_count buf) opts.max_lines))))

(fn get-lang [bufnr]
  (local ft (api.nvim_get_option_value "filetype" {:buf bufnr}))
  (if (or (not ft) (= ft ""))
      nil
      (let [(ok lang) (pcall vim.treesitter.language.get_lang ft)]
        (if (and ok lang) lang ft))))

(fn ensure-parser [bufnr]
  (local lang (get-lang bufnr))
  (when lang
    (let [(ok _) (pcall vim.treesitter.get_parser bufnr lang)]
      (when (not ok)
        (pcall vim.treesitter.start bufnr lang)))))

(fn get-query [lang]
  (let [(ok q) (pcall vim.treesitter.query.get lang "complexity")]
    (if (and ok q)
        (values q :complexity)
        (let [(ok* q*) (pcall vim.treesitter.query.get lang "textobjects")]
          (if (and ok* q*) (values q* :textobjects) (values nil nil))))))

(fn node-key [node]
  (let [(sr sc er ec) (node:range)]
    (.. sr ":" sc ":" er ":" ec)))

(fn function-capture? [name kind]
  (if (= kind :complexity)
      (= name "function")
      (or (= name "function.outer")
          (= name "method.outer"))))

(fn decision-capture? [name kind]
  (if (= kind :complexity)
      (= name "decision")
      (or (= name "conditional.outer")
          (= name "loop.outer"))))

(fn pick-hl-group [count]
  (if (and (= (type opts.hl_groups) :table)
           (= (type opts.severity_thresholds) :table))
      (let [medium (. opts.severity_thresholds :medium)
            high (. opts.severity_thresholds :high)]
        (if (and high (>= count high))
            (or (. opts.hl_groups :high) opts.hl_group)
            (and medium (>= count medium))
            (or (. opts.hl_groups :medium) opts.hl_group)
            (or (. opts.hl_groups :low) opts.hl_group)))
      opts.hl_group))

(fn format-text [count]
  (if (= opts.virt_text_pos "eol")
      (.. " " opts.prefix count)
      (.. opts.prefix count)))

(fn update-buffer [bufnr]
  (local buf (normalize-buf bufnr))
  (if (or (not opts.enabled) (not (buf-eligible? buf)))
      (clear-marks buf)
      (let [lang (get-lang buf)]
        (if (not lang)
            (clear-marks buf)
            (let [(ok parser) (pcall vim.treesitter.get_parser buf lang)]
              (if (not ok)
                  (clear-marks buf)
                  (let [trees (parser:parse)
                        tree (. trees 1)]
                    (if (not tree)
                        (clear-marks buf)
                        (let [root (tree:root)
                              (query kind) (get-query lang)]
                          (if (not query)
                              (clear-marks buf)
                              (let [captures (. query :captures)
                                    functions {}]

                                ;; Collect function-like nodes first.
                                (each [id node _ (query:iter_captures root buf 0 -1)]
                                  (let [cap (. captures id)]
                                    (when (function-capture? cap kind)
                                      (let [key (node-key node)]
                                        (tset functions key {:node node :count 1})))))

                                (let [has-functions (not= (next functions) nil)]
                                  (when (not has-functions)
                                    (clear-marks buf))
                                  (when has-functions
                                    ;; Accumulate decision nodes into the nearest function ancestor.
                                    (each [id node _ (query:iter_captures root buf 0 -1)]
                                      (let [cap (. captures id)]
                                        (when (decision-capture? cap kind)
                                          (var cur node)
                                          (var fkey nil)
                                          (while (and cur (not fkey))
                                            (let [key (node-key cur)]
                                              (if (. functions key)
                                                  (set fkey key)
                                                  (set cur (cur:parent)))))
                                          (when fkey
                                            (local info (. functions fkey))
                                            (set info.count (+ info.count 1)))))))

                                    ;; Render hints.
                                    (clear-marks buf)
                                    (each [_ info (pairs functions)]
                                      (let [count (. info :count)]
                                        (when (>= count opts.min)
                                          (let [node (. info :node)
                                                (sr _ _ _) (node:range)
                                                text (format-text count)
                                                hl-group (pick-hl-group count)]
                                            (api.nvim_buf_set_extmark
                                              buf
                                              ns-id
                                              sr
                                              0
                                              {:virt_text [[text hl-group]]
                                               :virt_text_pos opts.virt_text_pos
                                               :hl_mode "combine"}))))))))))))))))

)

(fn schedule-update [bufnr]
  (local buf (normalize-buf bufnr))
  (ensure-parser buf)
  (set seq (+ seq 1))
  (local token seq)
  (tset pending buf token)
  (vim.defer_fn
    (fn []
      (when (= (. pending buf) token)
        (tset pending buf nil)
        (update-buffer buf)))
    opts.debounce_ms))

(schedule.group "complexity_hints"
  [{:events ["BufEnter" "BufReadPost" "BufNewFile" "FileType"
             "BufWritePost" "InsertLeave" "TextChanged" "TextChangedI"]
    :opts {:desc "Update cyclomatic complexity hints"}
    :callback (fn [ev] (schedule-update ev.buf))}]
  {:clear true})
