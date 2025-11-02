(fn str? [x]
  "Check if `x` is a string."
  (= :string (type x)))

(local {: sym? : car} (require :fennel))
(local unpack (or (. table :unpack) (. _G :unpack)))

(fn expand-exprs [exprs]
  "Expand a list of expressions into multiple return values for macro output."
  (if (and exprs (= :table (type exprs)))
      (values (unpack exprs))
      exprs))

(lambda poincare! [...]
  "Declare modules to use in this configuration. Modules are defined in modules/.
  This macro was heavily inspired by the nyoom! macro in nyoom.nvim and the doom!
  macro in Doom Emacs."
  (var moduletag nil) ;; current module category
  (var registry {}) ;; registry of all modules

  (fn register-module [name]
    (if (str? name)
        ;; If `name` is a string, set it as the module category name
        (set moduletag name)
        (if (sym? name)
            (let [name (tostring name)
                  include-path (.. :fnl.modules. moduletag "." name)
                  config-path (.. :modules. moduletag "." name :.config)]
              (tset registry name
                    {:include-paths [include-path] :config-paths [config-path]}))
            (let [modulename (tostring (car name))
                  include-path (.. :fnl.modules. moduletag "." modulename)
                  config-path (.. :modules. moduletag "." modulename :.config)
                  [_ & flags] name]
              (var includes [include-path])
              (var configs [config-path])
              (each [_ v (ipairs flags)]
                (let [flagmodule (.. modulename "." (tostring v))
                      flag-include-path (.. include-path "." (tostring v))
                      flag-config-path (.. :modules. moduletag "." flagmodule
                                           :.config)]
                  (table.insert includes flag-include-path)
                  (table.insert configs flag-config-path)
                  (tset registry flagmodule {})))
              (tset registry modulename
                    {:include-paths includes :config-paths configs})))))

  (fn register-modules [...]
    (each [_ mod (ipairs [...])]
      (register-module mod))
    registry)

  ;; Make the registry globally visible to other macros
  (let [modules (register-modules ...)]
    (set _G.poincare/modules modules)))

(lambda poincare-init-modules! []
  "Initialise the module system"
  (fn init-module [module-name module-def]
    (icollect [_ include-path (ipairs (or module-def.include-paths []))]
      `(include ,include-path)))

  (fn init-modules [registry]
    (icollect [module-name module-def (pairs registry)]
      (init-module module-name module-def)))

  (let [inits (init-modules _G.poincare/modules)]
    (expand-exprs inits)))

(lambda poincare-compile-modules! []
  "Compile and cache modules"
  (fn compile-module [module-name module-decl]
    (icollect [_ config-path (ipairs (or module-decl.config-paths []))]
      `,(pcall require config-path)))

  (fn compile-modules [registry]
    (icollect [module-name module-def (pairs registry)]
      (compile-module module-name module-def)))

  (let [source (compile-modules _G.poincare/modules)]
    (expand-exprs [(unpack source)])))

{: poincare!
 : poincare-init-modules!
 : poincare-compile-modules!}
