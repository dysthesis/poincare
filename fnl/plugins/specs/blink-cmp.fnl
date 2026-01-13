(require-macros :plugins.helpers)

(use "blink.cmp"
  :event "InsertEnter"
  :after
  (fn []
    (local cmp (require :blink.cmp))
    (local mini-icons (require :mini.icons))
    (local comment-nodes ["comment" "line_comment" "block_comment"])

    (fn kind-icon-text [ctx]
      (local (kind-icon _ _) ((. mini-icons :get) "lsp" ctx.kind))
      kind-icon)

    (fn kind-icon-highlight [ctx]
      (local (_ hl _) ((. mini-icons :get) "lsp" ctx.kind))
      hl)

    (fn default-sources [_ctx]
      (local (ok node) (pcall vim.treesitter.get_node))
      (if (= vim.bo.filetype "lua")
          ["lsp" "path"]
          (and ok node (vim.tbl_contains comment-nodes (node:type)))
          ["buffer"]
          ["lsp" "path" "snippets" "buffer"]))

    ((. cmp :setup)
     {:completion
      {:accept {:auto_brackets {:enabled true}}
       :documentation {:auto_show true
                       :auto_show_delay_ms 0
                       :window {:border "single"}}
       :ghost_text {:enabled true}
       :menu {:border "rounded"
              :draw {:treesitter ["lsp"]
                     :gap 2
                     :components {:kind_icon
                                  {:ellipsis false
                                   :text kind-icon-text
                                   :highlight kind-icon-highlight}}}}}
      :fuzzy {:implementation "rust"}
      :appearance {:use_nvim_cmp_as_default false}
      :snippets {:preset "luasnip"}
      :signature {:enabled true}
      :cmdline {:completion {:ghost_text {:enabled false}}}
      :sources {:default default-sources}})))
