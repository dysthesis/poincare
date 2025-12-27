;; config/lsp.fnl
;; LSP defaults, diagnostics, and keymaps.

(local api vim.api)
(local vfn vim.fn)

(fn diagnostic-prefix [diagnostic]
  (let [client (vim.lsp.get_client_by_id diagnostic.source)
        label (or (?. client :name) diagnostic.source "")
        prefix (if (= label "") "" (.. label ": "))]
    (.. prefix diagnostic.message)))

(vim.diagnostic.config
  {:virtual_text {:format diagnostic-prefix}
   :underline true
   :signs
   {:text
    {[(. vim.diagnostic.severity :ERROR)] "󰅚 "
     [(. vim.diagnostic.severity :WARN)] "󰀪 "
     [(. vim.diagnostic.severity :INFO)] "󰋽 "
     [(. vim.diagnostic.severity :HINT)] "󰌶 "}
    :numhl
    {[(. vim.diagnostic.severity :ERROR)] "ErrorMsg"
     [(. vim.diagnostic.severity :WARN)] "WarningMsg"}}
   :update_in_insert false
   :severity_sort true})

;; NOTE: Define LSPs to enable here
(local lsps
  ["bash-language-server"
   "lua-language-server"
   "tinymist"
   ;; "rust-analyzer" -- rustaceanvim handles that instead
   "nixd"
   "zls"
   "texlab"
   "basedpyright"
   "gopls"
   "clangd"
   "fennel-ls"
   "ocamllsp"])

(each [_ lsp (ipairs lsps)]
  (when (= 1 (vfn.executable lsp))
    (vim.lsp.enable lsp)))

(api.nvim_create_autocmd "LspAttach"
  {:desc "LSP actions"
   :callback
   (fn [event]
     (set vim.lsp.handlers.textDocument/hover 
          (vim.lsp.with vim.lsp.handlers.hover {:focusable true}))
     (let [bufnr event.buf
           client (vim.lsp.get_client_by_id (?. event :data :client_id))
           opts {:buffer bufnr}]
       ;; Enable inlay hints if available
       (when (?. vim.lsp :inlay_hint)
         (vim.lsp.inlay_hint.enable true {:bufnr bufnr}))

       ;; Display documentation of the symbol under the cursor
       (vim.keymap.set "n" "K" vim.lsp.buf.hover opts)

       ;; Jump to the definition
       (vim.keymap.set "n" "gd" vim.lsp.buf.definition opts)

       ;; Format current file
       (vim.keymap.set ["n" "x"] "gq"
                       (fn [] (vim.lsp.buf.format {:async true}))
                       opts)

       ;; Displays a function's signature information
       (vim.keymap.set "i" "<C-s>" vim.lsp.buf.signature_help opts)

       ;; Jump to declaration
       (vim.keymap.set "n" "<leader>cd" vim.lsp.buf.declaration opts)

       ;; Lists all the implementations for the symbol under the cursor
       (vim.keymap.set "n" "<leader>ci" vim.lsp.buf.implementation opts)

       ;; Jumps to the definition of the type symbol
       (vim.keymap.set "n" "<leader>ct" vim.lsp.buf.type_definition opts)

       ;; Lists all the references
       (vim.keymap.set "n" "<leader>cR" vim.lsp.buf.references opts)

       ;; Selects a code action available at the current cursor position
       (vim.keymap.set "n" "<leader>ca" vim.lsp.buf.code_action opts)

       ;; Check if rustaceanvim is the client
       (when (and client (= client.name "rust-analyzer"))
         ;; Set up custom keybindings for rustaceanvim
         (vim.keymap.set "n" "K"
                         (fn [] (vim.cmd.RustLsp ["hover" "actions"]))
                         {:buffer bufnr :silent true}))))})
