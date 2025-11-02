(local fennel (require :fennel))

(fn str? [x]
  "Check if `x` is a string."
  (= :string (type x)))

(fn table? [x]
  (= :table (type x)))

(fn list? [x]
  ((. fennel :list?) x))

(fn sym? [x]
  ((. fennel :sym?) x))

(local gensym (. fennel :gensym))

(fn car [xs]
  (when (table? xs)
    (rawget xs 1)))

(fn assert-compile [condition message ...]
  (if condition
      condition
      (let [parts [message]]
        (each [_ extra (ipairs [...])]
          (table.insert parts (tostring extra)))
        (error (table.concat parts " ")))))

(local unpack (or (. table :unpack) (. _G :unpack)))

(fn expand-exprs [exprs]
  "Expand a list of expressions into multiple return values for macro output."
  (if (and exprs (= :table (type exprs)))
      (unpack exprs)
      exprs))

(lambda poincare! [...]
  "Declare modules to use in this configuration. Modules are defined in modules/.
  This macro was heavily inspired by the nyoom! macro in nyoom.nvim and the doom!
  macro in Doom Emacs."
  (var moduletag nil)
  ;; current module category
  (local registry {})
  ;; registry of all modules

  (fn register-module [name]
    (if (str? name)
        (set moduletag name)
        (if (= :table (type name))
            (let [modulename (tostring (car name))
                  ;; drop the "fnl." prefix; require searches fnl/… already
                  include-path (.. :modules. moduletag "." modulename)
                  config-path  (.. :modules. moduletag "." modulename :.config)
                  [_ & flags] name]
              (local includes [include-path])
              (local configs  [config-path])
              (each [_ v (ipairs flags)]
                (let [flag (tostring v)
                      flagmodule (.. modulename "." flag)
                      flag-include-path (.. include-path "." flag)
                      flag-config-path  (.. :modules. moduletag "." flagmodule :.config)]
                  (table.insert includes flag-include-path)
                  (table.insert configs flag-config-path)
                  (tset registry flagmodule {})))
              (tset registry modulename {:include-paths includes :config-paths configs}))
            (let [name (tostring name)
                  include-path (.. :modules. moduletag "." name)
                  config-path  (.. :modules. moduletag "." name :.config)]
              (tset registry name {:include-paths [include-path] :config-paths [config-path]})))))

  (fn register-modules [...]
    (each [_ mod (ipairs [...])]
      (register-module mod))
    registry)

  ;; Make the registry globally visible to other macros
  (let [modules (register-modules ...)]
    (set _G.poincare/modules modules)))

(lambda poincare-init-modules! []
  (fn init-module [_module-name module-def]
    (icollect [_ include-path (ipairs (or module-def.include-paths []))]
      ;; let the compiler alias static require->include
      `(require ,include-path)))
  (fn init-modules [registry]
    (icollect [_k module-def (pairs registry)]
      (init-module _k module-def)))
  (let [inits (init-modules _G.poincare/modules)]
    (expand-exprs inits)))

(lambda poincare-compile-modules! []
  "Compile and cache modules"
  (fn compile-module [module-name module-decl]
    (icollect [_ config-path (ipairs (or module-decl.config-paths []))]
      `(pcall require ,config-path)))

  (fn compile-modules [registry]
    (icollect [module-name module-def (pairs registry)]
      (compile-module module-name module-def)))

  (let [calls (compile-modules _G.poincare/modules)]
    (expand-exprs calls)))

(lambda plugin! [name ...]
  "Declare and configure a plugin, e.g. (plugin! \"telescope.nvim\" :cmd \"Telescope\" :opts {:defaults {:layout_strategy \"vertical\"}})"
  ;; basic validation
  (assert (str? name) "Plugin name must be a string")
  (local n (select "#" ...))
  (assert (= 0 (% n 2)) (.. "key-value varargs must be even; got " n))
  ;; capture the key/value pairs without evaluating them at macro-expansion time
  (var i 1)
  (local args [])
  (while (<= i n)
    (let [k (select i ...)
          v (select (+ i 1) ...)]
      (table.insert args k)
      (table.insert args v)
      (set i (+ i 2))))
  `((. (require :poincare.plugin) :register) ,name ,(unpack args)))


(fn nil? [x]
  (= nil x))

(fn tobool [x]
   (if x true false))

(fn begins-with? [chars str]
  "Returns `true` if the string `str` begins with the characters in `chars`, `false` otherwise.

  Arguments:
  * `chars`: the characters to check for at the beginning of `str`
  * `str`: the string to check

  Example:
  ```fennel
  (assert (= (begins-with? \"hello\" \"hello, world!\") true)
  (assert (= (begins-with? \"hey\" \"hello, world!\") false)
  ```"
  (tobool (str:match (.. "^" chars))))

(lambda fn? [x]
  "Checks if `x` is a function definition.
  Cannot check if a symbol is a function in compile time."
  (and (list? x) (or (= `fn (car x)) (= `hashfn (car x)) (= `lambda (car x))
                     (= `partial (car x)))))
(lambda quoted? [x]
  "Check if `x` is a list that begins with `quote`."
  (and (list? x) (= `quote (car x))))

(lambda quoted->fn [expr]
  "Converts an expression like `(quote (+ 1 1))` into `(fn [] (+ 1 1))`."
  (assert-compile (quoted? expr) "expected quoted expression for expr" expr)
  (let [non-quoted (. expr 2)]
    `(fn []
       ,non-quoted)))

(lambda set! [name ?value]
  "Set a vim option using the vim.opt.<name> API.
  Accepts the following arguments:
  name -> must be a symbol.
          - If it ends with '+' it appends to the current value.
          - If it ends with '-' it removes from the current value.
          - If it ends with with '^' it prepends to the current value.
  value -> anything.
           - If it is not specified, whether the name begins with 'no' is used
             as a boolean value.
           - If it is a quoted expression or a function it becomes
             v:lua.<symbol>()."
  (assert-compile (sym? name) "expected symbol for name" name)
  (let [name (tostring name)
        value (if (nil? ?value)
                  (not (begins-with? :no name))
                  ?value)
        value (if (quoted? value)
                  (quoted->fn value)
                  value)
        name (if (and (nil? ?value) (begins-with? :no name))
                 (name:match "^no(.+)$")
                 name)
        fn-sym (if (fn? value) (gensym "__") nil)
        exprs (if fn-sym [`(tset _G ,(tostring fn-sym) ,value)] [])
        value (if fn-sym (.. "v:lua." (tostring fn-sym)) value)
        exprs (doto exprs
                (table.insert (match (name:sub -1)
                                "+" `(: (. vim.opt ,(name:sub 1 -2)) :append
                                        ,value)
                                "-" `(: (. vim.opt ,(name:sub 1 -2)) :remove
                                        ,value)
                                "^" `(: (. vim.opt ,(name:sub 1 -2)) :prepend
                                        ,value)
                                _ `(tset vim.opt ,name ,value))))]
    (expand-exprs exprs)))

{: poincare! : poincare-init-modules! : poincare-compile-modules! : plugin!}
