;; lsp/rust-analyzer.fnl

(local lsp (require :utils.lsp))

(lsp.server
  {:filetypes ["rust"]
   :cmd ["rust-analyzer"]
   :settings
   {:cargo {:features "all"}

    :assist
    {:importEnforceGranularity true
     :importPrefix "crate"}

    :checkOnSave
    {:enable true
     :command "clippy"
     :features "all"}

    :inlayHints
    {:chainingHints
     {:bindingModeHints {:enable true}

      :chainingHints {:enable true}

      :closingBraceHints
      {:enable true
       :minLines 25}

      :closureCaptureHints {:enable true}

      :closureReturnTypeHints
      {:enable "always"}

      :closureStyle "impl_fn"

      :discriminantHints
      {:enable "always"}

      :expressionAdjustmentHints
      {:hideOutsideUnsafe false
       :mode "prefix"}

      :implicitDrops {:enable true}

      :lifetimeElisionHints
      {:enable "always"
       :useParameterNames true}

      :maxLength 25

      :parameterHints {:enable true}

      :rangeExclusiveHints {:enable true}

      :renderColons {:enable true}

      :typeHints
      {:enable true
       :hideClosureInitialization false
       :hideNamedConstructor false}}}

    :lens {:enable true}}})
