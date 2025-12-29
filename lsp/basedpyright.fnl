;; lsp/basedpyright.fnl

(local api vim.api)
(local lsp (require :utils.lsp))

(fn set-python-path [path-or-opts]
  (let [path (if (and (table? path-or-opts) (?. path-or-opts :args))
                 (. path-or-opts :args)
                 path-or-opts)
        bufnr (api.nvim_get_current_buf)
        clients (vim.lsp.get_clients
                  {:bufnr bufnr
                   :name "basedpyright"})]
    (each [_ client (ipairs clients)]
      (if client.settings
          (tset client.settings
                :python
                (vim.tbl_deep_extend "force"
                                     (or client.settings.python {})
                                     {:pythonPath path}))
          (tset client.config
                :settings
                (vim.tbl_deep_extend "force"
                                     (or client.config.settings {})
                                     {:python {:pythonPath path}})))
      (client:notify "workspace/didChangeConfiguration" {:settings nil}))))

(lsp.server
  {:cmd ["basedpyright-langserver" "--stdio"]
   :filetypes ["python"]
   :root_markers
   ["pyproject.toml"
    "setup.py"
    "setup.cfg"
    "requirements.txt"
    "Pipfile"
    "pyrightconfig.json"
    ".git"]
   :settings
   {:basedpyright
    {:analysis
     {:autoSearchPaths true
      :useLibraryCodeForTypes true
      :diagnosticMode "openFilesOnly"}}}
   :on_attach
   (fn [client bufnr]
     (api.nvim_buf_create_user_command
       bufnr
       "LspPyrightOrganizeImports"
       (fn []
         (client:exec_cmd
           {:command "basedpyright.organizeimports"
            :arguments [(vim.uri_from_bufnr bufnr)]}))
       {:desc "Organize Imports"})

     (api.nvim_buf_create_user_command
       bufnr
       "LspPyrightSetPythonPath"
       (fn [opts] (set-python-path (or (?. opts :args) opts)))
       {:desc "Reconfigure basedpyright with the provided python path"
        :nargs 1
        :complete "file"}))})
