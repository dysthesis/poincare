(local helpers (require :plugins.helpers))

(local M {})

(fn M.spec-paths []
  (var paths (vim.api.nvim_get_runtime_file 
               "lua/plugins/specs/*.lua" 
               true))
  (when (= 0 (# paths))
    (set paths (vim.api.nvim_get_runtime_file 
                 "fnl/plugins/specs/*.fnl" 
                 true)))
  (table.sort paths)
  paths)

(fn M.path->module [path]
  (let [rel (or (string.match path ".*/fnl/(.*)%.fnl$")
                (string.match path ".*/lua/(.*)%.lua$"))]
    (if rel
        (string.gsub rel "/" ".")
        nil)))

(fn M.spec-modules [paths]
  (local mods [])
  (local seen {})
  (each [_ path (ipairs paths)]
    (let [mod (M.path->module path)]
      (when (and mod (not (. seen mod)))
        (tset seen mod true)
        (table.insert mods mod))))
  mods)

(fn M.compile []
  (->> (M.spec-paths)
       (M.spec-modules)
       (helpers.setup)))

(M.compile)

M
