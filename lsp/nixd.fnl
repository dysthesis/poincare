;; lsp/nixd.fnl

(local lsp (require :utils.lsp))

(let [file (io.popen "hostname")]
  (when file
    (let [raw-hostname (or (file:read "*a") "")
          _ (file:close)
          hostname (raw-hostname:gsub "\n$" "")]
      (lsp.server
        {:cmd ["nixd"]
         :filetypes ["nix"]
         :root_markers ["flake.nix" "git"]
         :settings
         {:nixd
          {:nixpkgs {:expr "import <nixpkgs> { }"}
           :formatting {:command ["alejandra"]}
           :options
           {:nixos
            {:expr (.. "(builtins.getFlake (\"git+file://\" + toString ./.))"
                       ".nixosConfigurations."
                       hostname
                       ".options")}}}}}))))
