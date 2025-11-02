(fn str? [x]
  (= :string (type x)))

(fn table? [x]
  (= :table (type x)))

(fn deepcopy [value]
  (if (not (table? value))
      value
      (let [copy {}]
        (each [k v (pairs value)]
          (tset copy k (deepcopy v)))
        copy)))

(fn deep-merge [base extra]
  (if (not (table? base))
      (if (= extra nil) base extra)
      (if (not (table? extra))
          (if (= extra nil) base extra)
          (let [result (deepcopy base)]
            (each [k v (pairs extra)]
              (tset result k (deep-merge (rawget result k) v)))
            result))))

(fn normalize-opts [spec]
  (var acc nil)
  (when spec.opts
    (set acc (if (table? spec.opts) (deepcopy spec.opts) spec.opts)))
  (when spec.options
    (let [candidate (if (table? spec.options) (deepcopy spec.options)
                        spec.options)]
      (set acc (if (and (table? acc) (table? candidate))
                   (deep-merge acc candidate)
                   (or candidate acc)))))
  acc)

(fn ensure-defaults [spec]
  (when (= spec.lazy nil)
    (set spec.lazy false))
  (when (= spec.priority nil)
    (set spec.priority 1000)))

(fn build-spec [name ...]
  (let [name-str (if (= :string (type name)) name (tostring name))]
    (assert (str? name-str) "Plugin name must be a string")
    (let [spec {}]
      (tset spec 1 name-str)
      (var i 1)
      (while (<= i (select "#" ...))
        (let [k (select i ...)
              v (select (+ i 1) ...)]
          (tset spec k v)
          (set i (+ i 2))))
      (ensure-defaults spec)
      spec)))

(fn infer-main [name]
  ;; take last path segment and drop a trailing ".nvim"
  (let [seg (or (string.match name ".*/([^/]+)$") name)
        ;; call string.match directly; binding it to a local confuses some compilers
        base (or (string.match seg "(.+)%.nvim$") seg)]
    base))

(fn make-after [main-module base-opts user-after]
  (let [copy-opts (fn []
                    (if (table? base-opts)
                        (deepcopy base-opts)
                        base-opts))]
    (fn []
      (let [(ok plugin-or-err) (pcall require main-module)]
        (if (not ok)
            (error (.. "[plugin] failed to require " main-module ": "
                       plugin-or-err))
            (let [plugin plugin-or-err
                  setup (. plugin :setup)
                  callable (= :function (type setup))
                  merge-arg (fn [arg]
                              (if (not base-opts)
                                  arg
                                  (if (table? base-opts)
                                      (if (table? arg)
                                          (deep-merge (copy-opts) arg)
                                          (if (= arg nil) (copy-opts) arg))
                                      (if (= arg nil) base-opts arg))))]
              (var after-called false)
              (when callable
                (if user-after
                    (let [original setup]
                      (var setup-called false)
                      (local patched
                             (fn [...]
                               (set setup-called true)
                               (let [argc (select "#" ...)
                                     first-arg (if (> argc 0) (select 1 ...)
                                                   nil)
                                     merged (merge-arg first-arg)]
                                 (if (> argc 1)
                                     (let [rest (table.pack (select 2 ...))]
                                       (original merged (table.unpack rest)))
                                     (original merged)))))
                      (set plugin.setup patched)
                      (let [(ok-user err-user) (pcall user-after plugin
                                                      (copy-opts))]
                        (set plugin.setup original)
                        (if ok-user
                            (set after-called true)
                            (error err-user)))
                      (when (not setup-called)
                        (setup (copy-opts))))
                    (when base-opts
                      (setup (copy-opts)))))
              (when (and base-opts (not callable))
                (error (.. "Plugin " main-module
                           " received :opts/:options but exposes no callable setup()")))
              (when (and user-after (not after-called))
                (user-after plugin (copy-opts)))))))))

(fn register [name ...]
  (let [spec (build-spec name ...)
        base-opts (normalize-opts spec)
        user-after spec.after
        main (or spec.main (infer-main (. spec 1)))]
    (when spec.opts (set spec.opts nil))
    (when spec.options (set spec.options nil))
    (if base-opts
        (set spec.after (make-after main base-opts user-after))
        (when user-after
          (set spec.after user-after)))
    ((. (require :lz.n) :load) spec)))

{: register}
