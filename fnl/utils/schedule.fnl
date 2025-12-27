(local api vim.api)

(local M {})

(fn M._copy-keys [src dest keys]
  (each [_ k (ipairs keys)]
    (let [v (. src k)]
      (when (not= v nil)
        (tset dest k v)))))

(fn M.on [events ?opts f]
  (let [opts (or ?opts {})
        schedule? (if (not= nil (. opts :schedule)) (. opts :schedule) true)
        cb (if schedule?
               (fn [args]
                 (vim.schedule (fn [] (f args))))
               f)
        out {:callback cb}]
    (M._copy-keys opts out [:desc :pattern :once :nested :group :buffer])
    (api.nvim_create_autocmd events out)))

(fn M._normalise-modules [mods]
  (if (= nil mods)
      []
      (= (type mods) :string)
      [mods]
      (= (type mods) :table)
      mods
      (error "schedule: modules must be string or list")))

(fn M.require-all [mods]
  (each [_ mod (ipairs mods)]
    (require mod)))

(fn M.require-on [events modules ?opts]
  (let [mods (M._normalise-modules modules)]
    (when (> (# mods) 0)
      (local opts (or ?opts {}))
      (when (= nil (. opts :once))
        (set opts.once true))
      (M.on events opts (fn [] (M.require-all mods))))))

(fn M.group [name specs ?group-opts]
  (local id (api.nvim_create_augroup name (or ?group-opts {})))
  (each [_ spec (ipairs specs)]
    (local opts (vim.tbl_extend "force" {:group id} (or (. spec :opts) {})))
    (when (= nil (. opts :schedule))
      (tset opts :schedule false))
    (M.on (. spec :events) opts (. spec :callback))))

M
