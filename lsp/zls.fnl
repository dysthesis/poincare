;; lsp/zls.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:filetypes ["zig" "zon"]
   :cmd ["zls"]
   :root_markers ["build.zig" "build.zig.zon" ".git"]
   :settings
   {:zls
    {:enable_build_on_save true
     :build_on_save_step "check"}}})
