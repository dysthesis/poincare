;; lsp/clangd.fnl
;;
;; https://clangd.llvm.org/installation.html
;;
;; - Clang >= 11 is recommended.
;; - If compile_commands.json lives in a build directory, you should symlink it
;;   to the root of your source tree.
;; - clangd relies on a JSON compilation database specified as
;;   compile_commands.json.

(local api vim.api)
(local lsp (require :utils.lsp))

;; https://clangd.llvm.org/extensions.html#switch-between-sourceheader
(fn switch-source-header [bufnr client]
  (let [method-name "textDocument/switchSourceHeader"]
    (if (or (not client) (not (client:supports_method method-name)))
        (vim.notify
          (string.format
            "method %s is not supported by any servers active on the current buffer"
            method-name))
        (let [params (vim.lsp.util.make_text_document_params bufnr)]
          (client:request
            method-name
            params
            (fn [err result]
              (if err
                  (error (tostring err))
                  (if (not result)
                      (vim.notify "corresponding file cannot be determined")
                      (vim.cmd.edit (vim.uri_to_fname result)))))
            bufnr)))))

(fn symbol-info [bufnr client]
  (let [method-name "textDocument/symbolInfo"]
    (if (or (not client) (not (client:supports_method method-name)))
        (vim.notify "Clangd client not found" vim.log.levels.ERROR)
        (let [win (api.nvim_get_current_win)
              params (vim.lsp.util.make_position_params win client.offset_encoding)]
          (client:request
            method-name
            params
            (fn [err res]
              (if (or err (not res) (= (# res) 0))
                  nil
                  (let [info (. res 1)
                        container (string.format "container: %s" (?. info :containerName))
                        name (string.format "name: %s" (?. info :name))]
                    (vim.lsp.util.open_floating_preview
                      [name container]
                      ""
                      {:height 2
                       :width (math.max (string.len name) (string.len container))
                       :focusable false
                       :focus false
                       :title "Symbol Info"}))))
            bufnr)))))

(lsp.server
  {:cmd
   ["clangd"
    "--compile-commands-dir=build"
    "--query-driver=/usr/bin/**/aarch64-*-gnu-*,/nix/store/**/aarch64-*-gnu-*"
    "--log=verbose"]
   :filetypes ["c" "cpp" "objc" "objcpp" "cuda"]
   :root_markers
   [".clangd"
    ".clang-tidy"
    ".clang-format"
    "compile_commands.json"
    "compile_flags.txt"
    "configure.ac"
    ".git"]
   :capabilities
   {:textDocument {:completion {:editsNearCursor true}}
    :offsetEncoding ["utf-8" "utf-16"]}
   :on_init
   (fn [client init-result]
     (when (?. init-result :offsetEncoding)
       (tset client :offset_encoding (?. init-result :offsetEncoding))))
   :on_attach
   (fn [client bufnr]
     (api.nvim_buf_create_user_command
       bufnr
       "LspClangdSwitchSourceHeader"
       (fn [] (switch-source-header bufnr client))
       {:desc "Switch between source/header"})

     (api.nvim_buf_create_user_command
       bufnr
       "LspClangdShowSymbolInfo"
       (fn [] (symbol-info bufnr client))
       {:desc "Show symbol info"}))})
