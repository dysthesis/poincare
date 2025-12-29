(require-macros :plugins.helpers)

(local api vim.api)
(local km (require :utils.keymap))

(fn rust-lsp [subcmd]
  (fn [] (vim.cmd.RustLsp subcmd)))

(fn rustacean-opts []
  (local bufnr (api.nvim_get_current_buf))
  (local opts
    {:server
     {:default_settings
      {["rust-analyzer"]
       {:check {:command "clippy"
                :extraArgs ["--no-deps"]}
        :diagnostics {:experimental {:enabled true}}
        :cargo {:loadOutDirsFromCheck true
                :runBuildScripts true}
        :procMacro {:enable true}
        :inlayHints
        {:lifetimeElisionHints
         {:enable true
          :useParameterNames true}}}}}
     :dap
     {:adapter ((. (require :rustaceanvim.config) :get_codelldb_adapter)
                vim.g.codelldb_path
                vim.g.liblldb_path)}})

  (km.apply
    [["n" "<leader>dc" (rust-lsp "debuggables")
      {:desc "Rust debuggables"}]
     ["n" "<leader>dr" (rust-lsp "renderDiagnostic")
      {:desc "Rust render diagnostic"}]
     ["n" "<leader>de" (rust-lsp "explainError")
      {:desc "Rust explain error"}]]
    {:buffer bufnr
     :silent true})
  opts)

(use "rustaceanvim"
     :ft "rust"
     :before
     (fn []
       (set vim.g.rustaceanvim rustacean-opts)))
