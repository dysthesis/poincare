;; lsp/tinymist.fnl
;;
;; https://github.com/Myriad-Dreamin/tinymist
;; An integrated language service for Typst.
;;
;; Currently some of Tinymist's workspace commands are supported, namely:
;; LspTinymistExportSvg, LspTinymistExportPng, LspTinymistExportPdf,
;; LspTinymistExportMarkdown, LspTinymistExportText, LspTinymistExportQuery,
;; LspTinymistExportAnsiHighlight, LspTinymistGetServerInfo,
;; LspTinymistGetDocumentTrace, LspTinymistGetWorkspaceLabels,
;; LspTinymistGetDocumentMetrics, and LspTinymistPinMain.

(local api vim.api)

(fn create-tinymist-command [command-name client bufnr]
  (let [export-type (command-name:match "tinymist%.export(%w+)")
        info-type (command-name:match "tinymist%.(%w+)")
        cmd-display (if export-type
                        export-type
                        (-> info-type
                            (string.gsub "^get" "Get")
                            (string.gsub "^pin" "Pin")))
        cmd-name (if export-type
                     (.. "TinymistExport" cmd-display)
                     (.. "Tinymist" cmd-display))
        cmd-desc (if export-type
                     (.. "Export to " cmd-display)
                     (.. "Get " cmd-display))
        run-tinymist-command
        (fn []
          (let [arguments [(api.nvim_buf_get_name bufnr)]
                title-str (if export-type
                              (.. "Export " cmd-display)
                              cmd-display)
                handler
                (fn [err res]
                  (if err
                      (vim.notify (.. err.code ": " err.message)
                                  vim.log.levels.ERROR)
                      (vim.notify (vim.inspect res)
                                  vim.log.levels.INFO)))]
            (client:exec_cmd
              {:title title-str
               :command command-name
               :arguments arguments}
              {:bufnr bufnr}
              handler)))]
    (values run-tinymist-command cmd-name cmd-desc)))

{:cmd ["tinymist"]
 :filetypes ["typst"]
 :root_markers [".git"]
 :settings
 {:exportPdf "onType"
  :outputPath "$root/target/$dir/$name"
  :formatterMode "typstyle"
  :projectResolution "lockDatabase"}
 :on_attach
 (fn [client bufnr]
   (each [_ command (ipairs
                      ["tinymist.exportSvg"
                       "tinymist.exportPng"
                       "tinymist.exportPdf"
                       ;; "tinymist.exportHtml" -- Use typst 0.13
                       "tinymist.exportMarkdown"
                       "tinymist.exportText"
                       "tinymist.exportQuery"
                       "tinymist.exportAnsiHighlight"
                       "tinymist.getServerInfo"
                       "tinymist.getDocumentTrace"
                       "tinymist.getWorkspaceLabels"
                       "tinymist.getDocumentMetrics"
                       "tinymist.pinMain"]) ]
     (let [(cmd-fn cmd-name cmd-desc)
           (create-tinymist-command command client bufnr)]
       (api.nvim_buf_create_user_command
         bufnr
         (.. "Lsp" cmd-name)
         cmd-fn
         {:nargs 0 :desc cmd-desc})))

   (fn map [mode lhs rhs opts]
     (vim.keymap.set mode lhs rhs (or opts {})))

   (fn open-pdf []
     (let [filepath (api.nvim_buf_get_name 0)]
       (when (filepath:match "%.typ$")
         (let [pdf-path (filepath:gsub "%.typ$" ".pdf")]
           (vim.system ["open" pdf-path])))))

   (api.nvim_create_user_command "OpenPdf" open-pdf {})
   (map "n" "<leader>o" open-pdf {:desc "[O]pen PDF"}))}
